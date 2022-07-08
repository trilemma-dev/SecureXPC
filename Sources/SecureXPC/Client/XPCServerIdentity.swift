//
//  XPCServerIdentity.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-08
//

import Foundation

/// Information about the server an ``XPCClient`` is connected to.
///
/// Retrievable via ``XPCClient/serverIdentity`` or ``XPCClient/serverIdentity(_:)``.
///
/// ## Topics
/// ### Server Information
/// - ``code``
/// - ``effectiveUserID``
/// - ``effectiveGroupID``
public struct XPCServerIdentity {
    /// A represention of the server process.
    public let code: SecCode
    
    /// The effective user id of the server process.
    public let effectiveUserID: uid_t
    
    /// The effective group id of the server process.
    public let effectiveGroupID: gid_t
    
    /// It's intentional that the process id (PID) of the server process is not exposed since misuse of it can result in security vulnerabilities
    internal let processID: pid_t
}
