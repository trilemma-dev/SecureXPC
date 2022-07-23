//
//  ServerRequirement.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-07
//

import Foundation

public extension XPCClient {
    /// Determines whether a server should be trusted by an ``XPCClient``.
    ///
    /// If a server is trusted, `send` and `sendMessage` calls will be sent to it.
    ///
    /// Use a server requirement to retrieve a customized ``XPCClient`` for an XPC Mach service:
    /// ```swift
    /// let client = XPCClient.forXPCMachClient(named: "com.example.service",
    ///     withServerRequirement: try .sameBundle)
    /// ```
    ///
    /// Requirements can also be combined with `||` as well as `&&`:
    /// ```swift
    /// let client = XPCClient.forEndpoint(endpoint, withServerRequirement:
    ///     try .teamIdentifier("Q55ZG849VX") || try .sameTeamIdentifier)
    /// ```
    ///
    /// ## Topics
    /// ### Requirements
    /// - ``sameProcess``
    /// - ``sameBundle``
    /// - ``sameTeamIdentifier``
    /// - ``sameTeamIdentifierIfPresent``
    /// - ``teamIdentifier(_:)``
    /// - ``secRequirement(_:)``
    struct ServerRequirement {
        /// What actually performs the trust evaluation.
        private let serverAcceptor: ServerAcceptor
    }
}

extension XPCClient.ServerRequirement {
    /// The server must satisfy the specified code signing security requirement.
    public static func secRequirement(_ requirement: SecRequirement) -> XPCClient.ServerRequirement {
        XPCClient.ServerRequirement(serverAcceptor: SecRequirementServerAcceptor(requirement: requirement))
    }
    
    /// The server must have the specified team identifier.
    public static func teamIdentifier(_ teamIdentifier: String) throws -> XPCClient.ServerRequirement {
        .secRequirement(try secRequirementForTeamIdentifier(teamIdentifier))
    }
    
    /// The server must have the same team identifier as this client.
    ///
    /// - Throws: If this client does not have a team identifier.
    public static var sameTeamIdentifier: XPCClient.ServerRequirement {
        get throws {
            guard let teamID = try teamIdentifierForThisProcess() else {
                throw XPCError.misconfiguredClient(description: "This client does not have a team identifier")
            }
            
            return try teamIdentifier(teamID)
        }
    }
    
    // Exposing this publicly and having it be the default for a Mach service is a tradeoff of convenience vs security,
    // but in practice any production application ought to have a team identifier so it's a clear improvement over not
    // having any security requirement at all
    /// If this client has a team identifier, the server must have the same team identifier.
    ///
    /// If this client does not have a team identifier, any server will be trusted.
    public static var sameTeamIdentifierIfPresent: XPCClient.ServerRequirement {
        (try? .sameTeamIdentifier) ?? .alwaysAccepting
    }
    
    /// The server must be running in the same process.
    ///
    /// This is a convenient requirement when communicating with a server created via ``XPCServer/makeAnonymous()``.
    public static var sameProcess: XPCClient.ServerRequirement {
        // This is always safe to be public as a server requirement, unlike on the server side where in most cases it is
        // not safe to be a client requirement. What's fundamentally different is that the server had to be running at
        // the time this client communicated with it in order to ascertain its process id. There's no way for the server
        // to have terminated *prior* to this client starting and still have returned a response. As such, if they both
        // have the same process id then they *are* the same process.
        XPCClient.ServerRequirement(serverAcceptor: SameProcessServerAcceptor())
    }
    
    /// The server must be within this client's bundle.
    ///
    /// - Throws: If this client is not part of an application bundle.
    public static var sameBundle: XPCClient.ServerRequirement {
        get throws {
            // We need to determine this is actually a bundle and not a command line tool. This is because for a command
            // line tool, which is a single binary file, `Bundle.main.bundleURL` returns the directory the command line
            // tool is located in and that wouldn't provide the type of server requirement we're looking to establish.
            //
            // All .app and .xpc bundles have a structure of: <bundle>/Contents/MacOS/<main executable>
            // So we'll confirm this is the case or throw.
            guard let executableURL = Bundle.main.executableURL,
                  executableURL.deletingLastPathComponent() == Bundle.main.bundleURL
                                                                          .appendingPathComponent("Contents")
                                                                          .appendingPathComponent("MacOS") else {
                throw XPCError.misconfiguredClient(description: """
                This client is not part of an app or XPC service bundle.
                Bundle URL: \(Bundle.main.bundleURL)
                Executable URL: \(Bundle.main.executableURL?.description ?? "<not present>")
                """)
            }
            
            return XPCClient.ServerRequirement(serverAcceptor: SameBundleServerAcceptor())
        }
    }
    
    /// The server must satisfy both requirements.
    public static func && (
        lhs: XPCClient.ServerRequirement,
        rhs: XPCClient.ServerRequirement
    ) -> XPCClient.ServerRequirement {
        XPCClient.ServerRequirement(serverAcceptor: AndServerAcceptor(lhs: lhs.serverAcceptor, rhs: rhs.serverAcceptor))
    }
    
    /// The server must satisfy at least one of the requirements.
    public static func || (
        lhs: XPCClient.ServerRequirement,
        rhs: XPCClient.ServerRequirement
    ) -> XPCClient.ServerRequirement {
        XPCClient.ServerRequirement(serverAcceptor: OrServerAcceptor(lhs: lhs.serverAcceptor, rhs: rhs.serverAcceptor))
    }
    
    // MARK: Internal
    
    // This is intentionally not publicly exposed, it's only intended for default use by `XPCServiceClient`
    internal static var alwaysAccepting: XPCClient.ServerRequirement {
        XPCClient.ServerRequirement(serverAcceptor: AlwaysAcceptingServerAcceptor())
    }
    
    /// Determines whether a server should be trusted.
    internal func trustServer(_ serverIdentity: XPCClient.ServerIdentity) -> Bool {
        serverAcceptor.trustServer(serverIdentity)
    }
}

fileprivate protocol ServerAcceptor {
    /// Determines whether to trust a server.
    func trustServer(_ serverIdentity: XPCClient.ServerIdentity) -> Bool
}

/// This should only be used for XPC services which are application-scoped, so it's acceptable to assume the server is inheritently trusted.
fileprivate struct AlwaysAcceptingServerAcceptor: ServerAcceptor {
    func trustServer(_ serverIdentity: XPCClient.ServerIdentity) -> Bool {
        true
    }
}

fileprivate struct SameProcessServerAcceptor: ServerAcceptor {
    func trustServer(_ serverIdentity: XPCClient.ServerIdentity) -> Bool {
        getpid() == serverIdentity.processID
    }
}

fileprivate struct SecRequirementServerAcceptor: ServerAcceptor {
    let requirement: SecRequirement
    
    func trustServer(_ serverIdentity: XPCClient.ServerIdentity) -> Bool {
        SecCodeCheckValidity(serverIdentity.code, SecCSFlags(), self.requirement) == errSecSuccess
    }
}

/// Trusts a server which is located within this client's bundle.
fileprivate struct SameBundleServerAcceptor: ServerAcceptor {
    func trustServer(_ serverIdentity: XPCClient.ServerIdentity) -> Bool {
        guard let serverPathComponents = SecCodeCopyPath(serverIdentity.code)?.pathComponents else {
            return false
        }
        let clientPathComponents = Bundle.main.bundleURL.pathComponents
        
        // If this is true there's no possibility of the server being equal to or a subdirectory of this client bundle.
        // Importantly it also means when zipping that serverPathComponents is never the shorter one causing an
        // incorrect directory subset check.
        if serverPathComponents.count < clientPathComponents.count {
            return false
        }
        
        // Each component in the client path must be present in the server's path
        return zip(serverPathComponents, clientPathComponents).allSatisfy(==)
    }
}

fileprivate struct AndServerAcceptor: ServerAcceptor {
    let lhs: ServerAcceptor
    let rhs: ServerAcceptor
    
    func trustServer(_ serverIdentity: XPCClient.ServerIdentity) -> Bool {
        lhs.trustServer(serverIdentity) && rhs.trustServer(serverIdentity)
    }
}

fileprivate struct OrServerAcceptor: ServerAcceptor {
    let lhs: ServerAcceptor
    let rhs: ServerAcceptor
    
    func trustServer(_ serverIdentity: XPCClient.ServerIdentity) -> Bool {
        lhs.trustServer(serverIdentity) || rhs.trustServer(serverIdentity)
    }
}
