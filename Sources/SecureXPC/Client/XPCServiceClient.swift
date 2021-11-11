//
//  XPCServiceClient.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-08.
//

import Foundation

internal class XPCServiceClient: XPCClient {
	/// Creates and returns a connection for the XPC service represented by this client.
	///
	/// - Note: This client implementation intentionally does not store a reference to the ``xpc_connection_t`` as it can become
	/// invalid for numerous reasons. Since it's expected relatively few messages will be sent and the lowest possible
	/// latency isn't needed, it's simpler to always create the connection on demand each time a message is to be sent.
	internal override func createConnection() -> xpc_connection_t {
		let connection = xpc_connection_create(self.serviceName, nil)
		xpc_connection_set_event_handler(connection, { (event: xpc_object_t) in
			// A block *must* be set as the handler, even though this block does nothing.
			// If it were not set, a crash would occur upon calling xpc_connection_resume.
		})
		xpc_connection_resume(connection)

		return connection
	}
}
