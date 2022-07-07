//
//  XPCEndpointClient.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-12-04
//

import Foundation

/// A concrete implementation of ``XPCClient`` which creates a connection to an ``XPCServerEndpoint``.
///
/// In the case of this package, this is the only way to communicate with an `XPCAnonymousServer`. It is also how `XPCServiceServer` and
/// `XPCMachServer` are communicated with when accessed via an ``XPCServer/endpoint`` returned for them.
internal class XPCEndpointClient: XPCClient {
    
    private let endpoint: XPCServerEndpoint

    internal init(endpoint: XPCServerEndpoint, serverRequirement: XPCServerRequirement) {
        self.endpoint = endpoint
        super.init(serverRequirement: serverRequirement)
    }
    
    internal override func createConnection() -> xpc_connection_t {
        xpc_connection_create_from_endpoint(endpoint.endpoint)
    }
    
    public override var connectionDescriptor: XPCConnectionDescriptor {
        self.endpoint.connectionDescriptor
    }
}
