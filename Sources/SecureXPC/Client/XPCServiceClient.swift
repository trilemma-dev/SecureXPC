//
//  XPCServiceClient.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-08
//

import Foundation

/// A concrete implementation of ``XPCClient`` which can communicate with an XPC Service.
///
/// In the case of this framework, the XPC Service is expected to be represented by an `XPCServiceServer`.
internal class XPCServiceClient: XPCClient {
    /// Creates and returns a connection for the XPC service represented by this client.
    ///
    /// > Note: This client implementation intentionally does not store a reference to the ``xpc_connection_t`` as it can become
    /// invalid for numerous reasons. Since it's expected relatively few messages will be sent and the lowest possible
    /// latency isn't needed, it's simpler to always create the connection on demand each time a message is to be sent.
    internal override func createConnection() -> xpc_connection_t {
        xpc_connection_create(self.serviceName, nil)
    }
}
