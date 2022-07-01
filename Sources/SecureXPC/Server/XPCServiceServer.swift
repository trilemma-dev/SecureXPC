//
//  XPCServiceServer.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-07
//

import Foundation

/// A concrete implementation of ``XPCServer`` which acts as a server for an XPC service.
///
/// In the case of this framework, the XPC service is expected to be communicated with by an `XPCServiceClient`.
internal class XPCServiceServer: XPCServer {
    
    internal static var isThisProcessAnXPCService: Bool {
        // To be an XPC service this process needs to have a package type of XPC!, have an xpc file extension, and be
        // located in its parent's Contents/XPCServices directory
        return mainBundlePackageInfo().packageType == "XPC!" &&
        Bundle.main.bundleURL.pathExtension == "xpc" &&
        Bundle.main.bundleURL.deletingLastPathComponent().pathComponents.suffix(2) == ["Contents", "XPCServices"]
    }
    
    /// The server itself, there can only ever be one per process as there is only ever one named connection that exists for an XPC service
    private static let service = XPCServiceServer(messageAcceptor: AlwaysAcceptingMessageAcceptor())
    
    /// Whether this server has been started.
    private var started = false
    /// The serial queue used for handling retrieving an `endpoint`
    private let endpointQueue = DispatchQueue(label: String(describing: XPCServiceServer.self))
    /// Receives new incoming connections via the endpoint
    private var anonymousListenerConnection: xpc_connection_t?
    /// Connections received for the anonymous listener connection while the server is not started
    private var pendingConnections = [xpc_connection_t]()
        
    internal static func forThisXPCService() throws -> XPCServiceServer {
        // An XPC service's package type must be equal to "XPC!", see Apple's documentation for details
        // https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW6
        
        guard isThisProcessAnXPCService else {
            throw XPCError.misconfiguredServer(description: """
            This process is not an XPC service.
            Package type: \(mainBundlePackageInfo().packageType ?? "<not present>")
            Location: \(Bundle.main.bundleURL.path)
            """)
        }

        if Bundle.main.bundleIdentifier == nil {
            throw XPCError.misconfiguredServer(description: "An XPC service must have a CFBundleIdentifier")
        }
        
        return service
    }
    
    /// Returns a bundle’s package type and creator.
    private static func mainBundlePackageInfo() -> (packageType: String?, packageCreator: String?) {
        var packageType = UInt32()
        var packageCreator = UInt32()
        CFBundleGetPackageInfo(CFBundleGetMainBundle(), &packageType, &packageCreator)

        func uint32ToString(_ input: UInt32) -> String? {
            if input == 0 {
                return nil
            }
            var input = input
            return String(data: Data(bytes: &input, count: MemoryLayout<UInt32>.size), encoding: .utf8)
        }

        return (uint32ToString(packageType.bigEndian), uint32ToString(packageCreator.bigEndian))
    }

    public override func startAndBlock() -> Never {
        // Starts up any connections which were received for the anonymous listener connection which is used to have
        // this server provide an `endpoint`
        self.endpointQueue.sync {
            self.started = true
            self.pendingConnections.forEach(self.startClientConnection(_:))
            self.pendingConnections.removeAll()
        }
        
        xpc_main { connection in
            // This is a @convention(c) closure, so we can't just capture `self`.
            // As such, the singleton reference `XPCServiceServer.service` is used instead.
            XPCServiceServer.service.startClientConnection(connection)
        }
    }

    public override var connectionDescriptor: XPCConnectionDescriptor {
        // It's safe to force unwrap the bundle identifier because it was already checked in `forThisXPCService()`.
        .xpcService(name: Bundle.main.bundleIdentifier!)
    }
    
    public override var endpoint: XPCServerEndpoint {
        // There's seemingly no way to create an endpoint for an XPC service using the XPC C API. This is because
        // endpoints are only created from connection listeners, which an XPC service doesn't expose — incoming
        // connections are simply passed to the handler provided to `xpc_main(...)`. Specifically the documentation for
        // xpc_main says:
        //   This function will set up your service bundle's listener connection and manage it automatically.
        //
        // So instead we'll create an anonymous listener connection and then treat incoming connections identically to
        // as if they were coming from `xpc_main(...)`. To users of this API there should be no discernable difference
        // as both `xpc_main(...)` and the anonymous listener connection are fully encapsulated within this class.
        self.endpointQueue.sync {
            // Already created the listener connection previously
            if let anonymousListenerConnection = self.anonymousListenerConnection {
                return XPCServerEndpoint(connectionDescriptor: self.connectionDescriptor,
                                         endpoint: xpc_endpoint_create(anonymousListenerConnection))
            }
            
            // Otherwise, create the listener connection and start it
            let anonymousListenerConnection = xpc_connection_create(nil, nil)
            xpc_connection_set_event_handler(anonymousListenerConnection, { connection in
                if self.started {
                    self.startClientConnection(connection)
                } else {
                    self.pendingConnections.append(connection)
                }
            })
            xpc_connection_resume(anonymousListenerConnection)
            self.anonymousListenerConnection = anonymousListenerConnection
            
            // Now that any arbitrary process could create a connection to this server, the message acceptor needs to be
            // more restrictive. We'll allow any connection from a process belongs to the same parent bundle and if
            // there's a valid team ID present we'll additionally enforce it's of the same team ID.
            
            // XPC services are located in their parent's Contents/XPCServices directory
            let parentBundleURL = Bundle.main.bundleURL.deletingLastPathComponent() // <name>.xpc bundle directory
                                                       .deletingLastPathComponent() // XPCServices
                                                       .deletingLastPathComponent() // Contents
            let parentBundleAcceptor = ParentBundleMessageAcceptor(parentBundleURL: parentBundleURL)
            if let teamID = try? teamIdentifier(),
               let teamIDAcceptor = try? SecRequirementsMessageAcceptor(forTeamIdentifier: teamID) {
                self.messageAcceptor = AndMessageAcceptor(lhs: teamIDAcceptor, rhs: parentBundleAcceptor)
            } else {
                self.messageAcceptor = parentBundleAcceptor
            }
            
            return XPCServerEndpoint(connectionDescriptor: self.connectionDescriptor,
                                     endpoint: xpc_endpoint_create(anonymousListenerConnection))
        }
    }
}
