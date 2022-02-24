//
//  XPCServer.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// An XPC server to receive requests from and send responses to an ``XPCClient``.
///
/// ### Retrieving a Server
/// There are two different types of services you can retrieve a server for: XPC services and XPC Mach services. If you're uncertain which type of service you're
/// using, it's likely an XPC service.
///
/// Anonymous servers can also be created which do not correspond to an XPC service or XPC Mach service.
///
/// #### XPC services
/// These are helper tools which ship as part of your app and only your app can communicate with.
///
/// To retrieve a server for an XPC service:
/// ```swift
/// let server = try XPCServer.forThisXPCService()
/// ```
///
/// #### XPC Mach services
/// Launch Agents, Launch Daemons, and helper tools installed with
/// [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) can optionally communicate
/// over XPC by using Mach services.
///
/// In most cases, a server can be auto-configured for a helper tool installed with `SMJobBless`:
/// ```swift
/// let server = try XPCServer.forThisBlessedHelperTool()
/// ```
/// See ``XPCServer/forThisBlessedHelperTool()`` for the exact requirements which need to be met.
///
/// For Launch Agents, Launch Daemons, more advanced `SMJobBless` helper tool configurations, as well as other cases it is necessary both to the specify the
/// name of the service as well its security requirements. See ``XPCServer/forThisMachService(named:clientRequirements:)`` for an example and
/// details.
///
/// #### Anonymous servers
/// An anonymous server can be created by any macOS program. Use cases for making one include:
///  - Allowing two processes which are not XPC services to communicate over XPC with each other. This is done by having one of those processes make an
///    anonymous server and send its ``NonBlockingServer/endpoint`` to an XPC Mach service. The other process then needs to retrieve that endpoint
///    from the XPC Mach service and create a client using ``XPCClient/forEndpoint(_:)``.
///  - Testing code that would otherwise run as part of an XPC Mach service without needing to install a helper tool. However, note that this code won't run as root.
///
/// ### Registering & Handling Routes
/// Once a server instance has been retrieved, one or more routes should be registered with it. This is done by calling one of the `registerRoute` functions and
/// providing a route and a compatible closure or function. For example:
/// ```swift
///     ...
///     let updateConfigRoute = XPCRoute.named("update", "config")
///                                     .withMessageType(Config.self)
///                                     .withReplyType(Config.self)
///     server.registerRoute(updateConfigRoute, handler: updateConfig)
/// }
///
/// private func updateConfig(_ config: Config) throws -> Config {
///     <# implementation here #>
/// }
/// ```
///
/// ### Starting a Server
/// Once all of the routes are registered, the server must be told to start processing requests. In most cases this should be done with:
/// ```swift
/// server.startAndBlock()
/// ```
///
/// Returned server instances which conform to ``NonBlockingServer`` can also be started in a non-blocking manner:
/// ```swift
/// server.start()
/// ```
///
/// ## Topics
/// ### Retrieving a Server
/// - ``forThisXPCService()`` 
/// - ``forThisBlessedHelperTool()``
/// - ``forThisMachService(named:clientRequirements:)``
/// - ``makeAnonymous()``
/// - ``makeAnonymous(clientRequirements:)``
/// ### Registering Routes
/// - ``registerRoute(_:handler:)-4ttqe``
/// - ``registerRoute(_:handler:)-9a0x9``
/// - ``registerRoute(_:handler:)-4fxv0``
/// - ``registerRoute(_:handler:)-1jw9d``
/// ### Registering Async Routes
/// - ``registerRoute(_:handler:)-6htah``
/// - ``registerRoute(_:handler:)-g7ww``
/// - ``registerRoute(_:handler:)-rw2w``
/// - ``registerRoute(_:handler:)-2vk6u``
/// ### Configuring a Server
/// - ``targetQueue``
/// - ``setErrorHandler(_:)-lex4``
/// - ``setErrorHandler(_:)-1r3up``
/// ### Starting a Server
/// - ``startAndBlock()``
/// - ``NonBlockingServer/start()``
/// ### Server State
/// - ``serviceName``
/// - ``NonBlockingServer/endpoint``
public class XPCServer {
    
    /// Set of weak references to connections, used to update their dispatch queues.
    private var connections = Set<WeakConnection>()
    
    /// Weak wrapper around a connection stored in the `connections` variable.
    ///
    /// Designed to be conveniently settable as the context of an `xpc_connection_t` so that it's accessible from its finalizer.
    fileprivate class WeakConnection: Hashable {
        private weak var server: XPCServer?
        fileprivate weak var connection: xpc_connection_t?
        private let id = UUID()
        
        init(_ connection: xpc_connection_t, server: XPCServer) {
            self.connection = connection
            self.server = server
        }
        
        func removeFromContainer() {
            self.server?.connections.remove(self)
        }
        
        static func == (lhs: XPCServer.WeakConnection, rhs: XPCServer.WeakConnection) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            self.id.hash(into: &hasher)
        }
    }
    
    /// The queue used to run the handlers associated with registered routes.
    ///
    /// Applying the target queue is asynchronous and non-preemptive and therefore will not interrupt the execution of an already-running handler. The queue
    /// returned from reading this property will always be the one most recently set even if it is not yet the queue used to run handlers for all incoming requests.
    public var targetQueue: DispatchQueue? {
        willSet {
            connections.compactMap{ $0.connection }.forEach{ xpc_connection_set_target_queue($0, newValue) }
        }
    }
    
    // MARK: Route registration
    
    private var routes = [XPCRoute : XPCHandler]()
        
    /// Internal function that actually registers the route and enforces that a route is only ever registered once.
    ///
    /// All of the public functions exist to satisfy type constraints.
    private func registerRoute(_ route: XPCRoute, handler: XPCHandler) {
        if let _ = self.routes.updateValue(handler, forKey: route) {
            fatalError("Route \(route.pathComponents) is already registered")
        }
    }
    
    /// Registers a route that has no message and can't receive a reply.
    ///
    /// > Important: Routes can only be registered with a handler once; it is a programming error to provide a route which has already been registered.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute(_ route: XPCRouteWithoutMessageWithoutReply,
                              handler: @escaping () throws -> Void) {
        self.registerRoute(route.route, handler: ConstrainedXPCHandlerWithoutMessageWithoutReplySync(handler: handler))
    }
    
    /// Registers a route that has no message and can't receive a reply.
    ///
    /// > Important: Routes can only be registered with a handler once; it is a programming error to provide a route which has already been registered.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    @available(macOS 10.15.0, *)
    public func registerRoute(_ route: XPCRouteWithoutMessageWithoutReply,
                              handler: @escaping () async throws -> Void) {
        self.registerRoute(route.route, handler: ConstrainedXPCHandlerWithoutMessageWithoutReplyAsync(handler: handler))
    }
    
    /// Registers a route that has a message and can't receive a reply.
    ///
    /// > Important: Routes can only be registered with a handler once; it is a programming error to provide a route which has already been registered.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<M: Decodable>(_ route: XPCRouteWithMessageWithoutReply<M>,
                                            handler: @escaping (M) throws -> Void) {
        self.registerRoute(route.route, handler: ConstrainedXPCHandlerWithMessageWithoutReplySync(handler: handler))
    }
    
    /// Registers a route that has a message and can't receive a reply.
    ///
    /// > Important: Routes can only be registered with a handler once; it is a programming error to provide a route which has already been registered.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    @available(macOS 10.15.0, *)
    public func registerRoute<M: Decodable>(_ route: XPCRouteWithMessageWithoutReply<M>,
                                            handler: @escaping (M) async throws -> Void) {
        self.registerRoute(route.route, handler: ConstrainedXPCHandlerWithMessageWithoutReplyAsync(handler: handler))
    }
    
    /// Registers a route that has no message and expects a reply.
    ///
    /// > Important: Routes can only be registered with a handler once; it is a programming error to provide a route which has already been registered.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<R: Decodable>(_ route: XPCRouteWithoutMessageWithReply<R>,
                                            handler: @escaping () throws -> R) {
        self.registerRoute(route.route, handler: ConstrainedXPCHandlerWithoutMessageWithReplySync(handler: handler))
    }
    
    /// Registers a route that has no message and expects a reply.
    ///
    /// > Important: Routes can only be registered with a handler once; it is a programming error to provide a route which has already been registered.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    @available(macOS 10.15.0, *)
    public func registerRoute<R: Decodable>(_ route: XPCRouteWithoutMessageWithReply<R>,
                                            handler: @escaping () async throws -> R) {
        self.registerRoute(route.route, handler: ConstrainedXPCHandlerWithoutMessageWithReplyAsync(handler: handler))
    }
    
    /// Registers a route that has a message and expects a reply.
    ///
    /// > Important: Routes can only be registered with a handler once; it is a programming error to provide a route which has already been registered.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<M: Decodable, R: Encodable>(_ route: XPCRouteWithMessageWithReply<M, R>,
                                                          handler: @escaping (M) throws -> R) {
        self.registerRoute(route.route, handler: ConstrainedXPCHandlerWithMessageWithReplySync(handler: handler))
    }
    
    /// Registers a route that has a message and expects a reply.
    ///
    /// > Important: Routes can only be registered with a handler once; it is a programming error to provide a route which has already been registered.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    /// - Throws: If this route has already been registered.
    @available(macOS 10.15.0, *)
    public func registerRoute<M: Decodable, R: Encodable>(_ route: XPCRouteWithMessageWithReply<M, R>,
                                                          handler: @escaping (M) async throws -> R) {
        self.registerRoute(route.route, handler: ConstrainedXPCHandlerWithMessageWithReplyAsync(handler: handler))
    }
    
    internal func startClientConnection(_ connection: xpc_connection_t) {
        // Listen for events (messages or errors) coming from this connection
        xpc_connection_set_event_handler(connection, { event in
            self.handleEvent(connection: connection, event: event)
        })
        xpc_connection_set_target_queue(connection, self.targetQueue)
        self.addConnection(connection)
        xpc_connection_resume(connection)
    }
    
    private func addConnection(_ connection: xpc_connection_t) {
        // Keep a weak reference to the connection and this server, setting this as the context on the connection
        let weakConnection = WeakConnection(connection, server: self)
        self.connections.insert(weakConnection)
        xpc_connection_set_context(connection, Unmanaged.passRetained(weakConnection).toOpaque())
        
        // The finalizer is called when the connection's retain count has reached zero, so now we need to remove the
        // wrapper from the containing connections array
        xpc_connection_set_finalizer_f(connection, { opaqueWeakConnection in
            guard let opaqueWeakConnection = opaqueWeakConnection else {
                fatalError("Connection with retain count of zero is missing context, this should never happen")
            }
            
            let weakConnection = Unmanaged<WeakConnection>.fromOpaque(opaqueWeakConnection).takeRetainedValue()
            weakConnection.removeFromContainer()
        })
    }
    
    private func handleEvent(connection: xpc_connection_t, event: xpc_object_t) {
        // Only dictionary types and errors are expected. If it's not a dictionary and not an XPC C API error, then that
        // itself is an error and `XPCError.fromXPCObject` will properly handle this case.
        // Note that we're intentionally not checking for message acceptance as errors generated by libxpc can fail to
        // meet the acceptor's criteria because they're not coming from the client.
        guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else {
            self.errorHandler.handle(XPCError.fromXPCObject(event))
            return
        }
        
        guard self.messageAcceptor.acceptMessage(connection: connection, message: event) else {
            self.errorHandler.handle(.insecure)
            return
        }
        
        self.handleMessage(connection: connection, message: event)
    }
    
    private func handleMessage(connection: xpc_connection_t, message: xpc_object_t) {
        let request: Request
        do {
            request = try Request(dictionary: message)
        } catch {
            var reply = xpc_dictionary_create_reply(message)
            self.handleError(error, connection: connection, reply: &reply)
            return
        }
        
        guard let handler = self.routes[request.route] else {
            let error = XPCError.routeNotRegistered(request.route.pathComponents)
            var reply = xpc_dictionary_create_reply(message)
            self.handleError(error, connection: connection, reply: &reply)
            return
        }
        
        if let handler = handler as? XPCHandlerSync {
            var reply = xpc_dictionary_create_reply(message)
            do {
                try handler.handle(request: request, reply: &reply)
                
                // If a dictionary reply exists, then the message expects a reply to be sent back
                if let reply = reply {
                    xpc_connection_send_message(connection, reply)
                }
            } catch {
                self.handleError(error, connection: connection, reply: &reply)
            }
            
        } else if #available(macOS 10.15.0, *), let handler = handler as? XPCHandlerAsync {
            Task {
                var reply = xpc_dictionary_create_reply(message)
                do {
                    try await handler.handle(request: request, reply: &reply)
                    
                    // If a dictionary reply exists, then the message expects a reply to be sent back
                    if let reply = reply {
                        xpc_connection_send_message(connection, reply)
                    }
                } catch {
                    self.handleError(error, connection: connection, reply: &reply)
                }
            }
        } else {
            fatalError("Non-sync handler for route \(request.route.pathComponents) was found, but only sync routes " +
                       "should be registrable on this OS version. Handler: \(handler)")
        }
    }
    
    // MARK: Error handling
    
    /// Wrapper around an error handling closure to ensure there's only ever one error handler regardless of whether it's synchronous or asynchronous.
    fileprivate enum ErrorHandler {
        case none
        case sync((XPCError) -> Void)
        case async((XPCError) async -> Void)
        
        func handle(_ error: XPCError) {
            switch self {
                case .none:
                    break
                case .sync(let handler):
                    handler(error)
                case .async(let handler):
                    if #available(macOS 10.15, *) {
                        Task {
                            await handler(error)
                        }
                    } else {
                        fatalError("async error handler was set on macOS prior to 10.15, this should not be possible")
                    }
            }
        }
    }
    
    private var errorHandler = ErrorHandler.none
    
    /// Sets a handler to synchronously receive any errors encountered.
    ///
    /// This will replace any previously set error handler, including an asynchronous one.
    public func setErrorHandler(_ handler: @escaping (XPCError) -> Void) {
        self.errorHandler = .sync(handler)
    }
    
    /// Sets a handler to asynchronously receive any errors encountered.
    ///
    /// This will replace any previously set error handler, including a synchronous one.
    @available(macOS 10.15.0, *)
    public func setErrorHandler(_ handler: @escaping (XPCError) async -> Void) {
        self.errorHandler = .async(handler)
    }
    
    private func handleError(_ error: Error, connection: xpc_connection_t, reply: inout xpc_object_t?) {
        let error = XPCError.asXPCError(error: error)
        self.errorHandler.handle(error)
        
        // If it's possible to reply, then send the error back to the client
        if var reply = reply {
            do {
                try Response.encodeError(error, intoReply: &reply)
                xpc_connection_send_message(connection, reply)
            } catch {
                // If encoding the error fails, then there's no way to proceed
            }
        }
    }

	// MARK: Abstract methods & properties
    
    /// Begins processing requests received by this XPC server and never returns.
    ///
    /// If this server is for an XPC service, how the server will run is determined by the info property list's
    /// [`RunLoopType`](https://developer.apple.com/documentation/bundleresources/information_property_list/xpcservice/runlooptype?changes=l_3).
    /// If no value is specified, `dispatch_main` is the default. If `dispatch_main` is specified or defaulted to, it is a programming error to call this function
    /// from any thread besides the main thread.
    ///
    /// If this server is for a Mach service or is an anonymous server, it is always a programming error to call this function from any thread besides the main thread.
    public func startAndBlock() -> Never {
        fatalError("Abstract Method")
    }
    
    /// The name of the service this server is bound to.
    ///
    /// Anonymous servers do not represent a service and therefore will always have a `nil` service name.
    public var serviceName: String? {
        fatalError("Abstract Property")
    }
    
    /// Used to determine whether an incoming XPC message from a client should be processed and handed off to a registered route.
    internal var messageAcceptor: MessageAcceptor {
        fatalError("Abstract Property")
    }
}

// MARK: public server protocols

/// An ``XPCServer`` which can be started in a non-blocking manner.
///
/// > Warning: Do not implement this protocol. Additions made to this protocol will not be considered a breaking change for SemVer purposes.
public protocol NonBlockingServer {
    /// Begins processing requests received by this XPC server.
    func start()
    
    /// Retrieve an endpoint for this XPC server and then use ``XPCClient/forEndpoint(_:)`` to create a client.
    ///
    /// Endpoints can be sent across an XPC connection.
    var endpoint: XPCServerEndpoint { get }
    
    // Internal implementation note: `endpoint` is part of the `NonBlockingServer` protocol instead of `XPCServer` as
    // `XPCServiceServer` can't have an endpoint created for it.
    
    // From a technical perspective this is because endpoints are only created from connection listeners, which an XPC
    // service doesn't expose (incoming connections are simply passed to the handler provided to `xpc_main(...)`. From
    // a security point of view, it makes sense that it's not possible to create an endpoint for an XPC service because
    // they're designed to only allow communication between the main app and .xpc bundles contained within the same
    // main app's bundle. As such there's no valid use case for creating such an endpoint.
}

// MARK: public factories

// Contains all of the `static` code that provides the entry points to retrieving an `XPCServer` instance.
extension XPCServer {
    /// Provides a server for this XPC service.
    ///
    /// > Important: No requests will be processed until ``startAndBlock()`` is called.
    ///
    /// - Throws: ``XPCError/notXPCService`` if the caller is not an XPC service.
    /// - Returns: A server instance configured for this XPC service.
    public static func forThisXPCService() throws -> XPCServer {
        try XPCServiceServer._forThisXPCService()
    }
    
    /// Creates a new anonymous server that accepts requests from the same process it's running in.
    ///
    /// Only a client created from an anonymous server's endpoint can communicate with that server. Do this by retrieving the server's
    /// ``NonBlockingServer/endpoint`` and then creating a client with it:
    /// ```swift
    /// let server = XPCServer.makeAnonymous()
    /// let client = XPCClient.fromEndpoint(server.endpoint)
    /// ```
    ///
    /// > Important: No requests will be processed until ``NonBlockingServer/start()`` or ``startAndBlock()`` is called.
    ///
    /// > Note: If you need this server to be communicated with by clients running in a different process, use ``makeAnonymous(clientRequirements:)`` instead.
    public static func makeAnonymous() -> XPCServer & NonBlockingServer {
        XPCAnonymousServer(messageAcceptor: SameProcessMessageAcceptor())
    }

    /// Creates a new anonymous server that accepts requests from clients which meet the security requirements.
    ///
    /// Only a client created from an anonymous server's endpoint can communicate with that server. Retrieve the ``NonBlockingServer/endpoint`` and
    /// send it across an existing XPC connection. Because other processes on the system can talk to an anonymous server, when making a server it is required
    /// that you specifiy the
    /// [requirements](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
    /// of any connecting clients:
    /// ```swift
    /// let reqString = "identifier \"com.example.AuthorizedClient\" and certificate leaf[subject.OU] = \"4L0ZG128MM\""
    /// var requirement: SecRequirement?
    /// if SecRequirementCreateWithString(reqString as CFString,
    ///                                   SecCSFlags(),
    ///                                   &requirement) == errSecSuccess,
    ///    let requirement = requirement {
    ///     let server = XPCServer.makeAnonymous(clientRequirements: [requirement])
    ///
    ///     <# configure and start server #>
    /// }
    /// ```
    ///
    /// > Important: No requests will be processed until ``NonBlockingServer/start()`` or ``startAndBlock()`` is called.
    ///
    /// ## Requirements Checking
    /// On macOS 11 and later, requirement checking uses publicly documented APIs. On older versions of macOS, the private undocumented API
    /// `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)` will be used.  When requests are not accepted, if an
    /// error handler has been set then it is called with ``XPCError/insecure``.
    ///
    /// > Note: If you only need this server to be communicated with by clients running in the same process, use ``makeAnonymous()`` instead.
    ///
    /// - Parameters:
    ///   - clientRequirements: If a request is received from a client, it will only be processed if it meets one (or more) of these requirements.
    public static func makeAnonymous(clientRequirements: [SecRequirement]) -> XPCServer & NonBlockingServer {
        XPCAnonymousServer(messageAcceptor: SecureMessageAcceptor(requirements: clientRequirements))
    }
    
    /// Provides a server for this helper tool if it was installed with
    /// [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless).
    ///
    /// To successfully call this function the following requirements must be met:
    ///   - The launchd property list embedded in this helper tool must have exactly one entry for its `MachServices` dictionary
    ///   - The info property list embedded in this helper tool must have at least one element in its
    ///   [`SMAuthorizedClients`](https://developer.apple.com/documentation/bundleresources/information_property_list/smauthorizedclients)
    ///   array
    ///   - Every element in the `SMAuthorizedClients` array must be a valid security requirement
    ///     - To be valid, it must be creatable by
    ///     [`SecRequirementCreateWithString`](https://developer.apple.com/documentation/security/1394522-secrequirementcreatewithstring)
    ///
    /// Incoming requests will be accepted from clients that meet _any_ of the `SMAuthorizedClients` requirements.
    ///
    /// > Important: No requests will be processed until ``startAndBlock()`` or ``NonBlockingServer/start()`` is called.
    ///
    /// - Throws: ``XPCError/misconfiguredBlessedHelperTool(_:)`` if the configuration does not match this function's requirements.
    /// - Returns: A server instance configured with the embedded property list entries.
    public static func forThisBlessedHelperTool() throws -> XPCServer & NonBlockingServer {
        try XPCMachServer._forThisBlessedHelperTool()
    }

    /// Provides a server for this XPC Mach service that accepts requests from clients which meet the security requirements.
    ///
    /// For the provided server to function properly, the caller must be an XPC Mach service.
    ///
    /// Because many processes on the system can talk to an XPC Mach service, when retrieving a server it is required that you specifiy the
    /// [requirements](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
    /// of any connecting clients:
    /// ```swift
    /// let reqString = "identifier \"com.example.AuthorizedClient\" and certificate leaf[subject.OU] = \"4L0ZG128MM\""
    /// var requirement: SecRequirement?
    /// if SecRequirementCreateWithString(reqString as CFString,
    ///                                   SecCSFlags(),
    ///                                   &requirement) == errSecSuccess,
    ///   let requirement = requirement {
    ///     let server = XPCServer.forThisMachService(named: "com.example.service",
    ///                                               clientRequirements: [requirement])
    ///
    ///    <# configure and start server #>
    /// }
    /// ```
    /// > Important: No requests will be processed until ``startAndBlock()`` or ``NonBlockingServer/start()`` is called.
    ///
    /// ## Requirements Checking
    ///
    /// SecureXPC requires that a server for an XPC Mach service provide code signing requirements which define which clients are allowed to talk to it.
    ///
    /// On macOS 11 and later, requirement checking uses publicly documented APIs. On older versions of macOS, the private undocumented API
    /// `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)` will be used. When requests are not accepted, if an
    /// error handler has been set then it is called with ``XPCError/insecure``.
    ///
    /// - Parameters:
    ///   - named: The name of the Mach service this server should bind to. This name must be present in the launchd property list's `MachServices` entry.
    ///   - clientRequirements: If a request is received from a client, it will only be processed if it meets one (or more) of these requirements.
    /// - Throws: ``XPCError/conflictingClientRequirements`` if a server for this named service has previously been retrieved with different client
    ///           requirements.
    public static func forThisMachService(
        named machServiceName: String,
        clientRequirements: [SecRequirement]
    ) throws -> XPCServer & NonBlockingServer {
        try XPCMachServer.getXPCMachServer(named: machServiceName, clientRequirements: clientRequirements)
    }
}

// MARK: handler function wrappers

// These wrappers perform type erasure via their implemented protocols while internally maintaining type constraints
// This makes it possible to create heterogenous collections of them

fileprivate protocol XPCHandler {}

fileprivate extension XPCHandler {
    
    /// Validates that the incoming request matches the handler in terms of the presence of a message and reply.
    ///
    /// The actual validation of the types themselves is performed as part of encoding/decoding and is intentionally not checked by this function.
    ///
    /// - Parameters:
    ///   - request: The incoming request.
    ///   - reply: The XPC reply object, if one exists.
    ///   - messageType: The parameter type of the registered handler, if applicable.
    ///   - replyType: The return type of the registered handler, if applicable.
    /// - Throws: If the check fails.
    func checkMatchesRequest(_ request: Request,
                             reply: inout xpc_object_t?,
                             messageType: Any.Type?,
                             replyType: Any.Type?) throws {
        var errorMessages = [String]()
        // Message
        if messageType == nil, request.containsPayload {
            errorMessages.append("Request had a message of type \(String(describing: request.route.messageType)), " +
                                 "but the handler registered with the server does not have a message parameter.")
        } else if let messageType = messageType, !request.containsPayload {
            errorMessages.append("Request did not contain a message, but the handler registered with the server has " +
                                 "a message parameter of type \(messageType).")
        }
        
        // Reply
        if replyType == nil, reply != nil && request.route.expectsReply {
            errorMessages.append("Request expects a reply of type \(String(describing: request.route.replyType)), " +
                                 "but the handler registered with the server has no return value.")
        } else if let replyType = replyType, reply == nil {
            errorMessages.append("Request does not expect a reply, but the handler registered with the server has a " +
                                 "return value of type \(replyType).")
        }
        
        if !errorMessages.isEmpty {
            throw XPCError.routeMismatch(request.route.pathComponents, errorMessages.joined(separator: "\n"))
        }
    }
}

// MARK: sync handler function wrappers

fileprivate protocol XPCHandlerSync: XPCHandler {
    func handle(request: Request, reply: inout xpc_object_t?) throws
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithoutReplySync: XPCHandlerSync {
    let handler: () throws -> Void
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        try checkMatchesRequest(request, reply: &reply, messageType: nil, replyType: nil)
        try HandlerError.rethrow { try self.handler() }
    }
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithoutReplySync<M: Decodable>: XPCHandlerSync {
    let handler: (M) throws -> Void
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        try checkMatchesRequest(request, reply: &reply, messageType: M.self, replyType: nil)
        let decodedMessage = try request.decodePayload(asType: M.self)
        try HandlerError.rethrow { try self.handler(decodedMessage) }
    }
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithReplySync<R: Encodable>: XPCHandlerSync {
    let handler: () throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        try checkMatchesRequest(request, reply: &reply, messageType: nil, replyType: R.self)
        let payload = try HandlerError.rethrow { try self.handler() }
        try Response.encodePayload(payload, intoReply: &reply!)
    }
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithReplySync<M: Decodable, R: Encodable>: XPCHandlerSync {
    let handler: (M) throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        try checkMatchesRequest(request, reply: &reply, messageType: M.self, replyType: R.self)
        let decodedMessage = try request.decodePayload(asType: M.self)
        let payload = try HandlerError.rethrow { try self.handler(decodedMessage) }
        try Response.encodePayload(payload, intoReply: &reply!)
    }
}

// MARK: async handler function wrappers

@available(macOS 10.15.0, *)
fileprivate protocol XPCHandlerAsync: XPCHandler {
    func handle(request: Request, reply: inout xpc_object_t?) async throws
}

@available(macOS 10.15.0, *)
fileprivate struct ConstrainedXPCHandlerWithoutMessageWithoutReplyAsync: XPCHandlerAsync {
    let handler: () async throws -> Void
    
    func handle(request: Request, reply: inout xpc_object_t?) async throws {
        try checkMatchesRequest(request, reply: &reply, messageType: nil, replyType: nil)
        try await HandlerError.rethrow { try await self.handler() }
    }
}

@available(macOS 10.15.0, *)
fileprivate struct ConstrainedXPCHandlerWithMessageWithoutReplyAsync<M: Decodable>: XPCHandlerAsync {
    let handler: (M) async throws -> Void
    
    func handle(request: Request, reply: inout xpc_object_t?) async throws {
        try checkMatchesRequest(request, reply: &reply, messageType: M.self, replyType: nil)
        let decodedMessage = try request.decodePayload(asType: M.self)
        try await HandlerError.rethrow { try await self.handler(decodedMessage) }
    }
}

@available(macOS 10.15.0, *)
fileprivate struct ConstrainedXPCHandlerWithoutMessageWithReplyAsync<R: Encodable>: XPCHandlerAsync {
    let handler: () async throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t?) async throws {
        try checkMatchesRequest(request, reply: &reply, messageType: nil, replyType: R.self)
        let payload = try await HandlerError.rethrow { try await self.handler() }
        try Response.encodePayload(payload, intoReply: &reply!)
    }
}

@available(macOS 10.15.0, *)
fileprivate struct ConstrainedXPCHandlerWithMessageWithReplyAsync<M: Decodable, R: Encodable>: XPCHandlerAsync {
    let handler: (M) async throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t?) async throws {
        try checkMatchesRequest(request, reply: &reply, messageType: M.self, replyType: R.self)
        let decodedMessage = try request.decodePayload(asType: M.self)
        let payload = try await HandlerError.rethrow { try await self.handler(decodedMessage) }
        try Response.encodePayload(payload, intoReply: &reply!)
    }
}
