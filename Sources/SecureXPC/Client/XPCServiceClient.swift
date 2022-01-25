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

    override var serviceName: String? { xpcServiceName }

    internal init(xpcServiceName: String, connection: xpc_connection_t? = nil) {
        self.xpcServiceName = xpcServiceName
        super.init(connection: connection)
    }
    
    /// Creates and returns a connection for the XPC service represented by this client.
    internal override func createConnection() -> xpc_connection_t {
        xpc_connection_create(self.serviceName, nil)
    }
}
