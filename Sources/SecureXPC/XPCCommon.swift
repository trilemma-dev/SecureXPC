//
//  XPCCommon.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// A key into the XPC dictionary.
///
/// Instances of this type are part of the "packaging" format used by `Request` and `Response`.
typealias XPCDictionaryKey = UnsafePointer<CChar>

/// A helper function for defining C string constants, intended to have static lifetime.
/// - Parameter input: The input string literal, which will be copied into the result.
/// - Returns: A C string which can be stored indefinitely.
func const(_ input: UnsafePointer<CChar>!) -> UnsafePointer<CChar>! {
	let mutableCopy = strdup(input)!
	return UnsafePointer(mutableCopy) // The result should never actually be mutated
}

/// Thrown by a "fake" `Codable` instance such as ``XPCServerEndpoint`` or ``XPCFileDescriptorContainer`` which are only capable of being
/// encoded or decoded by the XPC coders, not an arbitrary coder.
///
/// This error is intentionally internal to the framework as we don't want API users to be trying to explicitly handle this specific case.
enum XPCCoderError: Error {
    case onlyDecodableBySecureXPCFramework
    case onlyEncodableBySecureXPCFramework
}

/// Determines the `SecCode` corresponding to an XPC connection and/or message.
///
/// Uses undocumented functionality prior to macOS 11.
func SecCodeCreateWithXPCConnection(_ connection: xpc_connection_t, andMessage message: xpc_object_t) -> SecCode? {
    // Get the code representing the client
    var code: SecCode?
    if #available(macOS 11, *) { // publicly documented, but only available since macOS 11
        SecCodeCreateWithXPCMessage(message, SecCSFlags(), &code)
    } else { // private undocumented function: xpc_connection_get_audit_token, available on prior versions of macOS
        let token = UndocumentedAuditToken.xpc_connection_get_audit_token(connection)
        let tokenValues = [token.val.0, token.val.1, token.val.2, token.val.3,
                           token.val.4, token.val.5, token.val.6, token.val.7]
        let tokenData = Data(bytes: tokenValues, count: tokenValues.count * MemoryLayout<UInt32>.size)
        let attributes = [kSecGuestAttributeAudit : tokenData] as CFDictionary
        SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
    }
    
    return code
}

/// Encapsulates the undocumented function `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
fileprivate struct UndocumentedAuditToken {
    
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
    fileprivate static func xpc_connection_get_audit_token(_ connection: xpc_connection_t) -> audit_token_t {
        var token = audit_token_t()
        xpc_connection_get_audit_tokenFunction(connection, &token)
        
        return token
    }
}
