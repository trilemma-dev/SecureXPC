//
//  XPCAnonymousClient.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-12-04
//

import Foundation

/// A concrete implementation of ``XPCClient`` which can communicate with an anonymous XPC listener connection.
///
/// In the case of this framework, the anonymous listener connection is expected to be represented by an `XPCAnonymousServer` or an `XPCServiceServer`
/// in the case where its `endpoint` is used.
internal class XPCAnonymousClient: XPCClient {
    // The connection descriptor is passed in as opposed to be always being `anonymous` because an anonymous client can
    // also be created to communicate with an endpoint returned by an XPCServiceServer and we want to preserve that
    // information so it's accessible to the end user.
    private let _connectionDescriptor: XPCConnectionDescriptor
    public override var connectionDescriptor: XPCConnectionDescriptor {
        _connectionDescriptor
    }

    // Anonymous clients *must* be created from an existing connection.
    internal init(connection: xpc_connection_t, connectionDescriptor: XPCConnectionDescriptor) {
        self._connectionDescriptor = connectionDescriptor
        super.init(connection: connection)
    }
    
    internal override func createConnection() throws -> xpc_connection_t {
        // Anonymous clients aren't capable of creating a new connection as there is no service to reconnect to
        throw XPCError.connectionCannotBeReestablished
    }
}
