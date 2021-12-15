//
//  XPCServerEndpoint.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import Foundation

// TODO: make this codable so it can be sent over XPC.
public struct XPCServerEndpoint {
    // Technically, an `xpc_endpoint_t` is sufficient to create a new connection, on its own. However, it's useful to
    // be able to communicate the kind of connection, and its name, so we also store those, separately.
    internal let serviceDescriptor: XPCServiceDescriptor
    internal let endpoint: xpc_endpoint_t

    internal init(serviceDescriptor: XPCServiceDescriptor, endpoint: xpc_endpoint_t) {
        self.serviceDescriptor = serviceDescriptor
        self.endpoint = endpoint
    }
}
