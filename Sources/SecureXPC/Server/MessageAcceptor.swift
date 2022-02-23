//
//  MessageAcceptor.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-01-06
//

import Foundation

internal protocol MessageAcceptor {
    /// Determines whether an incoming message should be accepted.
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool
}

/// This should only be used by XPC services which are application-scoped, so it's safe to assume they're inheritently safe.
internal struct AlwaysAcceptingMessageAcceptor: MessageAcceptor {
    static let instance = AlwaysAcceptingMessageAcceptor()
    
    private init() { }
    
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        true
    }
}

/// This is intended for use by `XPCAnonymousServer`.
internal struct SameProcessMessageAcceptor: MessageAcceptor {
    /// Accepts a message only if it is coming from this process.
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        // In the case of an XPCAnonymousServer, all of the connections must be created after the server itself was
        // created. As such, the process containing the server must always exist first and so no other process can
        // have the same PID while that process is still running. While it's possible the process now corresponding to
        // the PID returned by xpc_connection_get_pid(...) is not the process that created the connection, there's no
        // way for it fake being this process. Therefore for anonymous connections it's safe to directly compare PIDs.
        getpid() == xpc_connection_get_pid(connection)
    }
}

/// Accepts messages which meet the provided code signing requirements.
///
/// Uses undocumented functionality prior to macOS 11.
internal struct SecureMessageAcceptor: MessageAcceptor {
    /// At least one of these code signing requirements must be met in order for the message to be accepted
    internal let requirements: [SecRequirement]
    
    /// Accepts a message if it meets at least on of the provided `requirements`.
    ///
    /// If the `SecCode` of the process belonging to the other side of the connection could be not be determined, `false` is always returned.
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        guard let code = SecCodeCreateWithXPCConnection(connection, andMessage: message) else {
            return false
        }
        
        return self.requirements.contains { SecCodeCheckValidity(code, SecCSFlags(), $0) == errSecSuccess }
    }
}
