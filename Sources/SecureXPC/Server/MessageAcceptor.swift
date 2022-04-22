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
    
    /// Whether the `acceptor` is equivalent to this one.
    func isEqual(to acceptor: MessageAcceptor) -> Bool
}

extension MessageAcceptor {
    // Default implementation is based purely on matching types
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        return type(of: acceptor) == Self.self
    }
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
    static let instance = SameProcessMessageAcceptor()
    
    private init() { }
    
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
internal struct SecRequirementsMessageAcceptor: MessageAcceptor {
    /// At least one of these code signing requirements must be met in order for the message to be accepted
    private let requirements: [SecRequirement]
    
    internal init(_ requirements: [SecRequirement]) {
        self.requirements = requirements
    }
    
    /// Accepts a message if it meets at least on of the provided `requirements`.
    ///
    /// If the `SecCode` of the process belonging to the other side of the connection could be not be determined, `false` is always returned.
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        guard let code = SecCodeCreateWithXPCConnection(connection, andMessage: message) else {
            return false
        }
        
        return self.requirements.contains { SecCodeCheckValidity(code, SecCSFlags(), $0) == errSecSuccess }
    }
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        guard let acceptor = acceptor as? SecRequirementsMessageAcceptor else {
            return false
        }
        
        // Transform the requirements into Data form so that they can be compared
        let requirementTransform = { (requirement: SecRequirement) -> Data? in
            var data: CFData?
            if SecRequirementCopyData(requirement, SecCSFlags(), &data) == errSecSuccess, let data = data as Data? {
                return data
            } else {
                return nil
            }
        }
        
        // Turn into sets so they can be compared without taking into account the order of requirements
        let requirementsData = Set<Data>(self.requirements.compactMap(requirementTransform))
        let otherRequirementsData = Set<Data>(acceptor.requirements.compactMap(requirementTransform))
        
        return requirementsData == otherRequirementsData
    }
}

/// Accepts messages that originates from a directory containing this server.
internal struct ParentBundleMessageAcceptor: MessageAcceptor {
    
    static let instance = ParentBundleMessageAcceptor()
    
    private init() { }
    
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        guard let clientCode = SecCodeCreateWithXPCConnection(connection, andMessage: message),
              let clientPath = SecCodeCopyPath(clientCode) else {
            return false
        }
        
        var serverCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &serverCode) == errSecSuccess,
              let serverCode = serverCode,
              let serverPath = SecCodeCopyPath(serverCode) else {
            return false
        }
        
        // TODO: change this logic so any path within the parent bundle's directory is accepted
        // this will allow for other services, such as a Finder Sync Extension, to also communicate with the login item
        
        // If this is true, then the client path can't possibly be a parent directory
        if clientPath.pathComponents.count > serverPath.pathComponents.count {
            return false
        }
        
        // Validate the each component in the client path is present in the server in path in the same order
        for i in 0..<clientPath.pathComponents.count {
            if clientPath.pathComponents[i] != serverPath.pathComponents[i] {
                return false
            }
        }
        
        return true
    }
    
    /// This needs to be computed each time and not stored because it's entirely valid for a running app's bundle directory to be moved.
    /*
    private func parentBundleLocation() -> URL? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code = code,
              let path = SecCodeCopyPath(code) else {
            return nil
        }
        
        
        
        return nil
    }*/
    
    private func SecCodeCopyPath(_ code: SecCode) -> URL? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode = staticCode else {
            return nil
        }
        
        var path: CFURL?
        guard Security.SecCodeCopyPath(staticCode, SecCSFlags(), &path) == errSecSuccess,
              let path = (path as URL?)?.standardized else {
            return nil
        }
        
        return path
    }
}
