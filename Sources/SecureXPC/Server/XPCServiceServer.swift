//
//  XPCServiceServer.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-07
//

import XPC

/// A concrete implementation of ``XPCServer`` which acts as a server for an XPC Service.
///
/// In the case of this framework, the XPC Service is expected to be communicated with by an `XPCServiceClient`.
internal class XPCServiceServer: XPCServer {
    
	internal static let service = XPCServiceServer()

	private override init() {}

	public override func start() -> Never {
		xpc_main { connection in
			// Listen for events (messages or errors) coming from this connection
			xpc_connection_set_event_handler(connection, { event in
				XPCServiceServer.service.handleEvent(connection: connection, event: event)
			})
			xpc_connection_resume(connection)
		}
	}

	internal override func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
		// XPC services are application-scoped, so we're assuming they're inheritently safe
		true
	}
}
