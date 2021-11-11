//
//  XPCServiceServer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-07.
//

import XPC

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
