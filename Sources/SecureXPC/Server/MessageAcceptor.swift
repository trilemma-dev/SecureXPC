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

/// This should only be used by XPC services which are by default application-scoped, so it's acceptable to assume they're inheritently safe.
internal struct AlwaysAcceptingMessageAcceptor: MessageAcceptor {
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        true
    }
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        type(of: acceptor) == AlwaysAcceptingMessageAcceptor.self
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
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        type(of: acceptor) == SameProcessMessageAcceptor.self
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
    
    /// Initialized with the requirement the specified team identifier is present
    internal init(forTeamIdentifier teamIdentifier: String) throws {
        // From https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html
        // In regards to subject.OU:
        //     In Apple issued developer certificates, this field contains the developer’s Team Identifier.
        // The "anchor apple generic" portion effectively means the certificate chain was signed by Apple
        let requirementString = """
        anchor apple generic and certificate leaf[subject.OU] = "\(teamIdentifier)"
        """ as CFString
        
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString, [], &requirement) == errSecSuccess,
              let requirement = requirement else {
            let message = "Security requirement could not be created; textual representation: \(requirementString)"
            throw XPCError.internalFailure(description: message)
        }
        
        self.requirements = [requirement]
    }
    
    /// Accepts a message if it meets at least one of the provided `requirements`.
    ///
    /// If the `SecCode` of the process belonging to the other side of the connection could be not be determined, `false` is always returned.
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        do {
            try expandSandboxIfNecessary(message: message)
        } catch {
            return false
        }
        
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
    /// Requests must come from a process that either has the same URL as this or is a subdirectory of it.
    private let parentBundleURL: URL
    
    init(parentBundleURL: URL) {
        self.parentBundleURL = parentBundleURL
    }
    
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        do {
            try expandSandboxIfNecessary(message: message)
        } catch {
            return false
        }
        
        guard let clientCode = SecCodeCreateWithXPCConnection(connection, andMessage: message),
              let clientPath = SecCodeCopyPath(clientCode) else {
            return false
        }
        
        // If this is true there's no possibility of the client being equal to or a subdirectory of the parent bundle.
        // And importantly, this prevents indexing out of bounds when iterate through to check equality/containment.
        if clientPath.pathComponents.count < parentBundleURL.pathComponents.count {
            return false
        }
        
        // Validate the each component in the client path is present in the parent bundle path in the same order
        for i in 0..<parentBundleURL.pathComponents.count {
            if parentBundleURL.pathComponents[i] != clientPath.pathComponents[i] {
                return false
            }
        }
        
        return true
    }
    
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
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        guard let acceptor = acceptor as? ParentBundleMessageAcceptor else {
            return false
        }
        
        return acceptor.parentBundleURL == self.parentBundleURL
    }
}

/// Logically ands the results of two message acceptors.
struct AndMessageAcceptor: MessageAcceptor {
    private let lhs: MessageAcceptor
    private let rhs: MessageAcceptor
    
    init(lhs: MessageAcceptor, rhs: MessageAcceptor) {
        self.lhs = lhs
        self.rhs = rhs
    }
    
    func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        lhs.acceptMessage(connection: connection, message: message) &&
        rhs.acceptMessage(connection: connection, message: message)
    }
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        guard let acceptor = acceptor as? AndMessageAcceptor else {
            return false
        }
        
        return self.lhs.isEqual(to: acceptor.lhs) && self.rhs.isEqual(to: acceptor.rhs)
    }
}

/// If sandboxed, expands the sandbox by using a URL contained within the client's request.
private func expandSandboxIfNecessary(message: xpc_object_t) throws {
    // If we're sandboxed, in order to check the validity of the client process we need to expand our sandbox to include
    // the client's bundle. If the client is a legitimate SecureXPC client then the request will include a bookmark to
    // its bundle. If it's an attempted exploit, this poses some risk if there are vulnerabilities in decoding or in how
    // URL's initializer resolves the bookmark.
    if try isSandboxed() {
        let clientBookmark = try Request.decodeClientBookmark(dictionary: message)
        var isStale = Bool()
        // Creating this URL implicitly applies the bookmark's security scope
        // See https://developer.apple.com/forums//thread/704971?answerId=711609022
        _ = try URL(resolvingBookmarkData: clientBookmark, bookmarkDataIsStale: &isStale)
    }
}
