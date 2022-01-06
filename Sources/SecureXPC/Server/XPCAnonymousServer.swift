//
//  XPCAnonymousServer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import Foundation

internal class XPCAnonymousServer: XPCServer {
    private let anonymousListenerConnection: xpc_connection_t

    internal override init() {
        self.anonymousListenerConnection = xpc_connection_create(nil, nil)
        super.init()

        // Start listener for the new anonymous connection, all received events should be for incoming client connections
         xpc_connection_set_event_handler(anonymousListenerConnection, { newClientConnection in
             // Listen for events (messages or errors) coming from this connection
             xpc_connection_set_event_handler(newClientConnection, { event in
                 self.handleEvent(connection: newClientConnection, event: event)
             })
             xpc_connection_resume(newClientConnection)
         })
    }

    internal override func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        // Anonymous service connections should only ever passed among trusted parties.
        // TODO: add support for client security requirements https://github.com/trilemma-dev/SecureXPC/issues/36
        true
    }

    /// Begins processing requests received by this XPC server and never returns.
    public override func startAndBlock() -> Never {
        fatalError("startAndBlock() is not supported for anonymous connections. Use start() instead.")
    }

    public override var endpoint: XPCServerEndpoint {
        XPCServerEndpoint(
            serviceDescriptor: .anonymous,
            endpoint: xpc_endpoint_create(self.anonymousListenerConnection)
        )
    }
}

extension XPCAnonymousServer: NonBlockingStartable {
    public func start() {
        xpc_connection_resume(self.anonymousListenerConnection)
    }
}
