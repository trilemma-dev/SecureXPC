//
//  ClientRequirement.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-04
//

import Foundation

/// Determines whether a client's request should be routed to a request handler.
public indirect enum XPCClientRequirement {
    /// The requesting client must satisfy the specified code signing security requirement.
    case secRequirement(SecRequirement)
    
    /// The requesting client must have the specified team identifier.
    case teamIdentifier(String)
    
    /// The requesting client must have the same team identifier as this server.
    ///
    /// If this server does not have a team identifier, then this always evaluates to false.
    case sameTeamIdentifier
    
    /// The requesting client must be within the same parent app bundle as this server.
    ///
    /// If this server is not part of an app bundle, then this always evaluates to false.
    case sameAppBundle
    
    /// The requesting client must satisfy the designated requirement of the parent app bundle.
    ///
    /// If this server has no parent app bundle, then this always evaluates to false.
    case parentAppDesignatedRequirement
    
    /// The requesting client must be running in the same process as this server.
    case sameProcess
    
    /// The requesting client must satisfy both requirements.
    case and(XPCClientRequirement, XPCClientRequirement)
    
    /// The requesting client must satisfy at least one of the requirements.
    case or(XPCClientRequirement, XPCClientRequirement)
    
    internal var messageAcceptor: MessageAcceptor {
        get throws {
            switch self {
                case .secRequirement(let requirement):
                    return SecRequirementsMessageAcceptor([requirement])
                case .teamIdentifier(let teamIdentifier):
                    return try SecRequirementsMessageAcceptor(forTeamIdentifier: teamIdentifier)
                case .sameTeamIdentifier:
                    guard let teamID = try teamIdentifierForThisProcess() else {
                        return NeverAcceptingMessageAcceptor()
                    }
                    
                    return try SecRequirementsMessageAcceptor(forTeamIdentifier: teamID)
                case .sameAppBundle:
                    guard let parentBundleURL = try parentAppBundleURL() else {
                        return NeverAcceptingMessageAcceptor()
                    }
                    
                    return ParentBundleMessageAcceptor(parentBundleURL: parentBundleURL)
                case .parentAppDesignatedRequirement:
                    guard let parentBundleURL = try parentAppBundleURL() else {
                        return NeverAcceptingMessageAcceptor()
                    }
                    
                    var parentCode: SecStaticCode?
                    var parentRequirement: SecRequirement?
                    guard SecStaticCodeCreateWithPath(parentBundleURL as CFURL, [], &parentCode) == errSecSuccess,
                          let parentCode = parentCode,
                          SecCodeCopyDesignatedRequirement(parentCode, [], &parentRequirement) == errSecSuccess,
                          let parentRequirement = parentRequirement else {
                        return NeverAcceptingMessageAcceptor()
                    }
                    
                    return SecRequirementsMessageAcceptor([parentRequirement])
                case .sameProcess:
                    return SameProcessMessageAcceptor()
                case .and(let rhs, let lhs):
                    return AndMessageAcceptor(lhs: try lhs.messageAcceptor, rhs: try rhs.messageAcceptor)
                case .or(let rhs, let lhs):
                    return OrMessageAcceptor(lhs: try lhs.messageAcceptor, rhs: try rhs.messageAcceptor)
            }
        }
    }
}

private func parentAppBundleURL() throws -> URL? {
    let components = Bundle.main.bundleURL.pathComponents
    guard let contentsIndex = components.lastIndex(of: "Contents"),
          components[components.index(before: contentsIndex)].hasSuffix(".app") else {
        return nil
    }
    
    return URL(fileURLWithPath: "/" + components[1..<contentsIndex].joined(separator: "/"))
}
