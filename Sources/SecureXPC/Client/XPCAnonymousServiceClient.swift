//
//  XPCAnonymousServiceClient.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-12-04
//

import Foundation

/// A concrete implementation of ``XPCClient`` which can communicate with an anonymous XPC service.
///
/// In the case of this framework, the anonymous service is expected to be represented by an `XPCAnonymousServer`.
internal class XPCAnonymousServiceClient: XPCClient {
    override var serviceName: String? { nil }

    // Anonymous service clients *must* be created from an existing connection.
    init(connection: xpc_connection_t) {
        super.init(connection: connection)
    }
    
    internal override func createConnection() throws -> xpc_connection_t {
        // Anonymous clients aren't capable of creating a new connection as there is no service to reconnect to
        throw XPCError.connectionCannotBeReestablished
    }
}