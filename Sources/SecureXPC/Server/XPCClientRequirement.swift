//
//  ClientRequirement.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-04
//

import Foundation

/// Determines whether a client's request should be trusted by an ``XPCServer``.
///
/// If a client is trusted, its requests will attempt to be routed to a registered route handler.
///
/// Use a client requirement to retrieve a customized `XPCServer` instance:
/// ```swift
/// let server = XPCServer.forThisProcess(ofType: .machService(
///     name: "com.example.service",
///     clientRequirement: try .sameTeamIdentifier))
/// ```
///
/// Requirements can be combined with `||` as well as `&&`:
/// ```swift
/// let server = XPCServer.makeAnonymous(withClientRequirement:
///     try .sameTeamIdentifier || try .teamIdentifier("Q55ZG849VX")))
/// ```
///
/// ## Topics
/// ### Requirements
/// - ``sameParentBundle``
/// - ``sameTeamIdentifier``
/// - ``teamIdentifier(_:)``
/// - ``parentDesignatedRequirement`` 
/// - ``secRequirement(_:)``
public struct XPCClientRequirement {
    /// What actually performs the requirement validation
    private let messageAcceptor: MessageAcceptor
    
    /// The requesting client must satisfy the specified code signing security requirement.
    public static func secRequirement(_ requirement: SecRequirement) -> XPCClientRequirement {
        XPCClientRequirement(messageAcceptor: SecRequirementsMessageAcceptor([requirement]))
    }
    
    /// The requesting client must have the specified team identifier.
    public static func teamIdentifier(_ teamIdentifier: String) throws -> XPCClientRequirement {
        .secRequirement(try secRequirementForTeamIdentifier(teamIdentifier))
    }
    
    /// The requesting client must have the same team identifier as this server.
    ///
    /// - Throws: If this server does not have a team identifier.
    public static var sameTeamIdentifier: XPCClientRequirement {
        get throws {
            guard let teamID = try teamIdentifierForThisProcess() else {
                throw XPCError.misconfiguredServer(description: "This server does not have a team identifier")
            }
            
            return try teamIdentifier(teamID)
        }
    }
    
    /// The requesting client must be within the same parent bundle as this server.
    ///
    /// - Throws: If this server is not part of a bundle.
    public static var sameParentBundle: XPCClientRequirement {
        get throws {
            XPCClientRequirement(messageAcceptor: ParentBundleMessageAcceptor(parentBundleURL: try parentBundleURL))
        }
    }
    
    /// The requesting client must satisfy the designated requirement of the parent bundle.
    ///
    /// - Throws: If this server has no parent bundle.
    public static var parentDesignatedRequirement: XPCClientRequirement {
        get throws {
            let parentBundleURL = try parentBundleURL
            var parentCode: SecStaticCode?
            var parentRequirement: SecRequirement?
            guard SecStaticCodeCreateWithPath(parentBundleURL as CFURL, [], &parentCode) == errSecSuccess,
                  let parentCode = parentCode,
                  SecCodeCopyDesignatedRequirement(parentCode, [], &parentRequirement) == errSecSuccess,
                  let parentRequirement = parentRequirement else {
                throw XPCError.internalFailure(description: "Unable to determine designated requirement for parent " +
                                                            "bundle: \(parentBundleURL)")
            }
            
            return secRequirement(parentRequirement)
        }
    }
    
    /// The requesting client must satisfy both requirements.
    public static func && (lhs: XPCClientRequirement, rhs: XPCClientRequirement) -> XPCClientRequirement {
        XPCClientRequirement(messageAcceptor: AndMessageAcceptor(lhs: lhs.messageAcceptor, rhs: rhs.messageAcceptor))
    }
    
    /// The requesting client must satisfy at least one of the requirements.
    public static func || (lhs: XPCClientRequirement, rhs: XPCClientRequirement) -> XPCClientRequirement {
        XPCClientRequirement(messageAcceptor: OrMessageAcceptor(lhs: lhs.messageAcceptor, rhs: rhs.messageAcceptor))
    }
    
    // MARK: Internal
    
    // This is intentionally not publicly exposed, it's only intended for default use by `XPCServiceServer`
    internal static var alwaysAccepting: XPCClientRequirement {
        XPCClientRequirement(messageAcceptor: AlwaysAcceptingMessageAcceptor())
    }
    
    
    // This is intentionally not publicly exposed as it's only safe to use for an `XPCAnonymousServer`
    // See SameProcessMessageAcceptor for more details
    internal static var sameProcess: XPCClientRequirement {
        get {
            XPCClientRequirement(messageAcceptor: SameProcessMessageAcceptor())
        }
    }
    
    /// Determines whether an incoming message should be accepted.
    internal func shouldAcceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        self.messageAcceptor.shouldAcceptMessage(connection: connection, message: message)
    }
    
    // MARK: Helpers
    
    private static var parentBundleURL: URL {
        get throws {
            let components = Bundle.main.bundleURL.pathComponents
            guard let contentsIndex = components.lastIndex(of: "Contents") else {
                throw XPCError.misconfiguredServer(description: "This server does not have a parent bundle.\n" +
                                                                "Path components: \(components)")
            }
            
            return URL(fileURLWithPath: "/" + components[1..<contentsIndex].joined(separator: "/"))
        }
    }
}

extension XPCClientRequirement: Equatable {
    public static func == (lhs: XPCClientRequirement, rhs: XPCClientRequirement) -> Bool {
        return lhs.messageAcceptor.isEqual(to: rhs.messageAcceptor)
    }
}

// MARK: Internal implementation

// A `MessageAccceptor` is essentially the internal implementation for an `XPCClientRequirement`

fileprivate protocol MessageAcceptor {
    /// Determines whether an incoming message should be accepted.
    func shouldAcceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool
    
    /// Whether the `acceptor` is equivalent to this one.
    func isEqual(to acceptor: MessageAcceptor) -> Bool
}

/// This should only be used by XPC services which are by default application-scoped, so it's acceptable to assume they're inheritently safe.
fileprivate struct AlwaysAcceptingMessageAcceptor: MessageAcceptor {
    func shouldAcceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        true
    }
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        acceptor is AlwaysAcceptingMessageAcceptor
    }
}

/// This is intended for use by `XPCAnonymousServer`.
fileprivate struct SameProcessMessageAcceptor: MessageAcceptor {
    /// Accepts a message only if it is coming from this process.
    func shouldAcceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        // In the case of an XPCAnonymousServer, all of the connections must be created after the server itself was
        // created. As such, the process containing the server must always exist first and so no other process can
        // have the same PID while that process is still running. While it's possible the process now corresponding to
        // the PID returned by xpc_connection_get_pid(...) is not the process that created the connection, there's no
        // way for it fake being this process. Therefore for anonymous connections it's safe to directly compare PIDs.
        getpid() == xpc_connection_get_pid(connection)
    }
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        acceptor is SameProcessMessageAcceptor
    }
}

/// Accepts messages which meet the provided code signing requirements.
///
/// Uses undocumented functionality prior to macOS 11.
fileprivate struct SecRequirementsMessageAcceptor: MessageAcceptor {
    /// At least one of these code signing requirements must be met in order for the message to be accepted
    private let requirements: [SecRequirement]
    
    internal init(_ requirements: [SecRequirement]) {
        self.requirements = requirements
    }
    
    /// Accepts a message if it meets at least one of the provided `requirements`.
    ///
    /// If the `SecCode` of the process belonging to the other side of the connection could be not be determined, `false` is always returned.
    func shouldAcceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
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
fileprivate struct ParentBundleMessageAcceptor: MessageAcceptor {
    /// Requests must come from a process that either has the same URL as this or is a subdirectory of it.
    private let parentBundleURL: URL
    
    init(parentBundleURL: URL) {
        self.parentBundleURL = parentBundleURL
    }
    
    func shouldAcceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
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
        // And importantly, this ensures that when zipping the server path components is never the shorter one causing
        // an incorrect directory subset check.
        if clientPath.pathComponents.count < parentBundleURL.pathComponents.count {
            return false
        }
        
        // Validate the each component in the client path is present in the parent bundle path in the same order
        return zip(parentBundleURL.pathComponents, clientPath.pathComponents).allSatisfy(==)
    }
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        guard let acceptor = acceptor as? ParentBundleMessageAcceptor else {
            return false
        }
        
        return acceptor.parentBundleURL == self.parentBundleURL
    }
}

/// Logically ands the results of two message acceptors.
fileprivate struct AndMessageAcceptor: MessageAcceptor {
    private let lhs: MessageAcceptor
    private let rhs: MessageAcceptor
    
    init(lhs: MessageAcceptor, rhs: MessageAcceptor) {
        self.lhs = lhs
        self.rhs = rhs
    }
    
    func shouldAcceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        lhs.shouldAcceptMessage(connection: connection, message: message) &&
        rhs.shouldAcceptMessage(connection: connection, message: message)
    }
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        guard let acceptor = acceptor as? AndMessageAcceptor else {
            return false
        }
        
        return self.lhs.isEqual(to: acceptor.lhs) && self.rhs.isEqual(to: acceptor.rhs)
    }
}

/// Logically ors the results of two message acceptors.
fileprivate struct OrMessageAcceptor: MessageAcceptor {
    private let lhs: MessageAcceptor
    private let rhs: MessageAcceptor
    
    init(lhs: MessageAcceptor, rhs: MessageAcceptor) {
        self.lhs = lhs
        self.rhs = rhs
    }
    
    func shouldAcceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        lhs.shouldAcceptMessage(connection: connection, message: message) ||
        rhs.shouldAcceptMessage(connection: connection, message: message)
    }
    
    func isEqual(to acceptor: MessageAcceptor) -> Bool {
        guard let acceptor = acceptor as? OrMessageAcceptor else {
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
