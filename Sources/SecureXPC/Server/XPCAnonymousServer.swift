//
//  XPCAnonymousServer.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import Foundation

internal class XPCAnonymousServer: XPCServer {
    private let anonymousListenerConnection: xpc_connection_t
    
    /// Determines if an incoming request can be handled based on the provided client requirements
    private let messageAcceptor: SecureMessageAcceptor

    internal init(clientRequirements: [SecRequirement]) {
        self.anonymousListenerConnection = xpc_connection_create(nil, nil)
        self.messageAcceptor = SecureMessageAcceptor(requirements: clientRequirements)
        super.init()
        self.addConnection(self.anonymousListenerConnection)
    }

    internal override func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
        self.messageAcceptor.acceptMessage(connection: connection, message: message)
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
        // Start listener for the new anonymous connection, all received events should be for incoming client connections
        xpc_connection_set_event_handler(anonymousListenerConnection, { newClientConnection in
            // Listen for events (messages or errors) coming from this connection
            xpc_connection_set_event_handler(newClientConnection, { event in
                self.handleEvent(connection: newClientConnection, event: event)
            })
            xpc_connection_set_target_queue(newClientConnection, self.targetQueue)
            self.addConnection(newClientConnection)
            xpc_connection_resume(newClientConnection)
        })
        xpc_connection_resume(self.anonymousListenerConnection)
    }
}
