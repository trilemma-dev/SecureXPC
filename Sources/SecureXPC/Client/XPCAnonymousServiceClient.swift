//
//  XPCAnonymousServiceClient.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-12-04
//

import Foundation

/// A concrete implementation of ``XPCClient`` which can communicate with an anonymous XPC service.
///
/// In the case of this framework, the Mach service is expected to be represented by an `XPCMachServer`.
internal class XPCAnonymousServiceClient: XPCClient {
    override var serviceName: String? { nil }

    // Anonymous service clients *must* be created from an existing connection.
    init(connection: xpc_connection_t) {
        super.init(connection: connection)
    }

    /// Creates and returns a connection for the Mach service represented by this client.
    internal override func createConnection() -> xpc_connection_t {
        fatalError("Anonymous XPC connections cannot be restarted.")
    }
}
