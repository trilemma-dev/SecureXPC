//
//  SecureMessageAcceptor.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-01-06
//

import Foundation

/// Accepts messages which meet the provided code signing requirements.
///
/// Uses undocumented functionality prior to macOS 11.
internal struct SecureMessageAcceptor {
    /// At least one of these code signing requirements must be met in order for the message to be accepted
    internal let requirements: [SecRequirement]
    
    /// Accepts a message if it meets at least on of the provided `requirements`.
    ///
    /// If the `SecCode` of the process belonging to the other side of the connection could be not be determined, `false` is always returned.
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        // Get the code representing the client
        var code: SecCode?
        if #available(macOS 11, *) { // publicly documented, but only available since macOS 11
            SecCodeCreateWithXPCMessage(message, SecCSFlags(), &code)
        } else { // private undocumented function: xpc_connection_get_audit_token, available on prior versions of macOS
            var auditToken = SecureMessageAcceptor.xpc_connection_get_audit_token(connection)
            let tokenData = NSData(bytes: &auditToken, length: MemoryLayout.size(ofValue: auditToken))
            let attributes = [kSecGuestAttributeAudit : tokenData] as NSDictionary
            SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
        }
        guard let code = code else { // Instead of explitly checking the return codes from the SecCode* function calls
            return false
        }
        
        // Accept message if code is valid and meets any of the client requirements
        return self.requirements.contains { SecCodeCheckValidity(code, SecCSFlags(), $0) == errSecSuccess }
    }
    
    // MARK: xpc_connection_get_audit_token
    
    /// The function signature of  `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
    private typealias get_audit_token = @convention(c) (xpc_connection_t, UnsafeMutablePointer<audit_token_t>) -> Void
    
    /// Represents the private undocumented function `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
    /// If the function does exist, but does not match the expected signature, then when this variable is loaded the process accessing this variable will crash.
    /// However, this variable should only be access on older versions of macOS which are expected to have a stable non-changing API so this should not occur.
    ///
    /// If this function can't be loaded for some version, a fatalError will intentonally be raised as this should never occur on an older version of macOS supported by
    /// SecureXPC.
    ///
    /// Note that because static variables are implicitly lazy the code to populate this variable never run unless this variable is accessed.
    private static var xpc_connection_get_audit_tokenFunction: get_audit_token = {
        // From man dlopen 3: If a null pointer is passed in path, dlopen() returns a handle equivalent to RTLD_DEFAULT
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            fatalError("dlopen call to retrieve RTLD_DEFAULT unexpectedly failed, this should never happen")
        }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "xpc_connection_get_audit_token") else {
            // Include macOS version number to assist in reproducing any reported issues
            fatalError("Function xpc_connection_get_audit_token could not be loaded while running on " +
                       ProcessInfo.processInfo.operatingSystemVersionString)
        }
        
        return unsafeBitCast(sym, to: get_audit_token.self)
    }()
    
    /// Wrapper around the private undocumented function `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
    ///
    /// - Parameters:
    ///   - _:  The connection for which the audit token will be retrieved for.
    /// - Returns: The audit token.
    private static func xpc_connection_get_audit_token(_ connection: xpc_connection_t) -> audit_token_t {
        var token = audit_token_t()
        xpc_connection_get_audit_tokenFunction(connection, &token)
        
        return token
    }
}
