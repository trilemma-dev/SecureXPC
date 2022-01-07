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
    
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        // Get the code representing the client
        var code: SecCode?
        if #available(macOS 11, *) { // publicly documented, but only available since macOS 11
            SecCodeCreateWithXPCMessage(message, SecCSFlags(), &code)
        } else { // private undocumented function: xpc_connection_get_audit_token, available on prior versions of macOS
            guard var auditToken = xpc_connection_get_audit_token(connection) else {
                return false
            }
            
            let tokenData = NSData(bytes: &auditToken, length: MemoryLayout.size(ofValue: auditToken))
            let attributes = [kSecGuestAttributeAudit : tokenData] as NSDictionary
            SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
        }

        // Accept message if code is valid and meets any of the client requirements
        guard let code = code else {
            return false
        }
        
        return self.requirements.contains { SecCodeCheckValidity(code, SecCSFlags(), $0) == errSecSuccess }
    }
    
    /// Wrapper around the private undocumented function `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
    ///
    /// The private undocumented function will attempt to be dynamically loaded and then invoked. If no function exists with this name `nil` will be returned. If
    /// the function does exist, but does not match the expected signature, the process calling this function is expected to crash. However, because this is only
    /// called on older versions of macOS which are expected to have a stable non-changing API this is very unlikely to occur.
    ///
    /// - Parameters:
    ///   - _:  The connection for which the audit token will be retrieved for.
    /// - Returns: The audit token or `nil` if the function could not be called.
    private func xpc_connection_get_audit_token(_ connection: xpc_connection_t) -> audit_token_t? {
        // Attempt to dynamically load the function
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "xpc_connection_get_audit_token") else {
            return nil
        }
        typealias functionSignature = @convention(c) (xpc_connection_t, UnsafeMutablePointer<audit_token_t>) -> Void
        let function = unsafeBitCast(sym, to: functionSignature.self)

        // Call the function
        var token = audit_token_t()
        function(connection, &token)
        
        return token
    }
}
