//
//  XPCConnectionDescriptor.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import Foundation

/// The type of connections serviced by an ``XPCServer`` or created by an ``XPCClient``.
public enum XPCConnectionDescriptor {
    /// An anonymous connection which has no associated service.
    case anonymous
    
    /// A connection for an XPC service.
    ///
    /// The associated value is the name of the service.
    case xpcService(name: String)
    
    /// A connection for an XPC Mach service.
    ///
    /// The associated value is the name of the service.
    case machService(name: String)
}

extension XPCConnectionDescriptor: Codable { }
