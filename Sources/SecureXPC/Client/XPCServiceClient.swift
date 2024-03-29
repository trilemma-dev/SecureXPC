//
//  XPCServiceClient.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-08
//

import Foundation

/// A concrete implementation of ``XPCClient`` which can communicate with an XPC service.
///
/// In the case of this framework, the XPC service is expected to be represented by an `XPCServiceServer`.
internal class XPCServiceClient: XPCClient {
    private let xpcServiceName: String

    public override var connectionDescriptor: XPCConnectionDescriptor {
        .xpcService(name: xpcServiceName)
    }

    internal init(xpcServiceName: String, serverRequirement: XPCClient.ServerRequirement) {
        self.xpcServiceName = xpcServiceName
        super.init(serverRequirement: serverRequirement)
    }
    
    /// Creates and returns a connection for the XPC service represented by this client.
    internal override func createConnection() -> xpc_connection_t {
        xpc_connection_create(self.xpcServiceName, nil)
    }
}
