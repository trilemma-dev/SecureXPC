//
//  XPCAnonymousServer.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import Foundation

internal class XPCAnonymousServer: XPCServer {
    /// Receives new incoming connections
    private let anonymousListenerConnection: xpc_connection_t
    /// The dispatch queue used when new connections are being received
    private let listenerQueue = DispatchQueue(label: String(describing: XPCAnonymousServer.self))
    /// Whether this server has been started, if not connections are added to pendingConnections
    private var started = false
    /// Connections received while the server is not started
    private var pendingConnections = [xpc_connection_t]()
    /// Determines if an incoming request will be accepted based on the provided client requirements
    private let _messageAcceptor: MessageAcceptor
    override internal var messageAcceptor: MessageAcceptor {
        _messageAcceptor
    }
    
    internal init(messageAcceptor: MessageAcceptor) {
        self._messageAcceptor = messageAcceptor
        self.anonymousListenerConnection = xpc_connection_create(nil, listenerQueue)
        super.init()
        
        // Configure listener for new anonymous connections, all received events are incoming client connections
        xpc_connection_set_event_handler(self.anonymousListenerConnection, { connection in
            if self.started {
                self.startClientConnection(connection)
            } else {
                self.pendingConnections.append(connection)
            }
        })
        xpc_connection_resume(self.anonymousListenerConnection)
    }

    /// Begins processing requests received by this XPC server and never returns.
    public override func startAndBlock() -> Never {
        self.start()
        dispatchMain()
    }

    internal func simulateDisconnectionForTesting() {
        xpc_connection_cancel(self.anonymousListenerConnection)
        // A new event handler must be set otherwise the existing one will still be used even after cancellation
        xpc_connection_set_event_handler(self.anonymousListenerConnection, { _ in })
    }
}

extension XPCAnonymousServer: NonBlockingServer {
    public func start() {
        self.listenerQueue.sync {
            self.started = true
            for connection in self.pendingConnections {
                self.startClientConnection(connection)
            }
            self.pendingConnections.removeAll()
        }
    }
    
    public var endpoint: XPCServerEndpoint {
        XPCServerEndpoint(
            serviceDescriptor: .anonymous,
            endpoint: xpc_endpoint_create(self.anonymousListenerConnection)
        )
    }
}
