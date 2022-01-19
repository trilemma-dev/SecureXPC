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
/// There are two different types of services you can retrieve a server for: XPC Services and XPC Mach services. If you're uncertain which type of service you're
/// using, it's likely an XPC Service.
///
/// #### XPC Services
/// These are helper tools which ship as part of your app and only your app can communicate with.
///
/// To retrieve a server for an XPC Service:
/// ```swift
/// let server = try XPCServer.forThisXPCService()
/// ```
///
/// #### XPC Mach services
///
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
/// **Requirement Checking**
///
/// SecureXPC requires that a server for an XPC Mach service provide code signing requirements which define which clients are allowed to talk to it.
///
/// On macOS 11 and later, requirement checking uses publicly documented APIs. On older versions of macOS, the private undocumented API
/// `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)` will be used; if for some reason the function is unavailable
/// then no messages will be accepted. When messages are not accepted, if the ``XPCServer/errorHandler`` is set then it is called
/// with ``XPCError/insecure``.
///
///
/// ### Registering & Handling Routes
/// Once a server instance has been retrieved, one or more routes should be registered with it. This is done by calling one of the `registerRoute` functions and
/// providing a route and a compatible closure or function. For example:
/// ```swift
///     ...
///     let updateConfigRoute = XPCRouteWithMessageWithReply("update", "config",
///                                                          messageType:Config.self,
///                                                          replyType: Config.self)
///     server.registerRoute(updateConfigRoute, handler: updateConfig)
/// }
///
/// private func updateConfig(_ config: Config) throws -> Config {
///     <# implementation here #>
/// }
/// ```
///
/// If the function or closure provided as the `handler` parameter throws an error and the route expects a return, then ``XPCError/other(_:)`` will be
/// returned to the client with the `String` associated type describing the thrown error. It is intentional the thrown error is not marshalled as that type may not be
/// `Codable` and may not exist in the client.
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
///
/// ### Registering Routes
/// - ``registerRoute(_:handler:)-82935``
/// - ``registerRoute(_:handler:)-7yvyr``
/// - ``registerRoute(_:handler:)-3ohmq``
/// - ``registerRoute(_:handler:)-4jjs6`` 
///
/// ### Starting a Server
/// - ``startAndBlock()``
/// - ``NonBlockingServer/start()``
///
/// ### Error Handling
/// - ``errorHandler``
public class XPCServer {

    // MARK: Public factories
    
    /// Provides a server for this XPC Service.
    ///
    /// For the provided server to function properly, the caller must be an XPC Service.
    ///
    /// > Important: No requests will be processed until ``startAndBlock()`` is called.
    ///
    /// - Throws: ``XPCError/notXPCService`` if the caller is not an XPC Service.
    /// - Returns: A server instance configured for this XPC Service.
    public static func forThisXPCService() throws -> XPCServer {
        try XPCServiceServer._forThisXPCService()
    }
    
    /// Creates a new anonymous server that only accepts connections from the same process it's running in.
    internal static func makeAnonymous() -> XPCServer & NonBlockingServer {
        XPCAnonymousServer(messageAcceptor: SameProcessMessageAcceptor())
    }

    internal static func makeAnonymous(clientRequirements: [SecRequirement]) -> XPCServer & NonBlockingServer {
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
    /// let reqString = """identifier "com.example.AuthorizedClient" and certificate leaf[subject.OU] = "4L0ZG128MM" """
    /// var requirement: SecRequirement?
    /// if SecRequirementCreateWithString(reqString as CFString,
    ///                                   SecCSFlags(),
    ///                                   &requirement) == errSecSuccess,
    ///   let requirement = requirement {
    ///    let server = XPCServer.forThisMachService(named: "com.example.service",
    ///                                              clientRequirements: [requirement])
    ///
    ///    <# configure and start server #>
    /// }
    /// ```
    ///
    /// > Important: No requests will be processed until ``startAndBlock()`` or ``NonBlockingServer/start()`` is called.
    ///
    /// - Parameters:
    ///   - named: The name of the mach service this server should bind to. This name must be present in the launchd property list's `MachServices` entry.
    ///   - clientRequirements: If a request is received from a client, it will only be processed if it meets one (or more) of these requirements.
    /// - Throws: ``XPCError/conflictingClientRequirements`` if a server for this named service has previously been retrieved with different client
    ///           requirements.
    public static func forThisMachService(
        named machServiceName: String,
        clientRequirements: [SecRequirement]
    ) throws -> XPCServer & NonBlockingServer {
        try XPCMachServer.getXPCMachServer(named: machServiceName, clientRequirements: clientRequirements)
    }

    // MARK: Implementation

    /// If set, errors encountered will be sent to this handler.
    public var errorHandler: ((XPCError) -> Void)?
    
    // Routes
    private var routes = [XPCRoute : XPCHandler]()
    
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
    
    /// Registers a route that has no message and can't receive a reply.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    /// - Throws: If this route has already been registered.
    public func registerRoute(_ route: XPCRouteWithoutMessageWithoutReply,
                              handler: @escaping () throws -> Void) throws {
        if self.routes.keys.contains(route.route) {
            throw XPCError.routeAlreadyRegistered(route.route.pathComponents)
        }
        
        self.routes[route.route] = ConstrainedXPCHandlerWithoutMessageWithoutReply(handler: handler)
    }
    
    /// Registers a route that has a message and can't receive a reply.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    /// - Throws: If this route has already been registered.
    public func registerRoute<M: Decodable>(_ route: XPCRouteWithMessageWithoutReply<M>,
                                            handler: @escaping (M) throws -> Void) throws {
        if self.routes.keys.contains(route.route) {
            throw XPCError.routeAlreadyRegistered(route.route.pathComponents)
        }
        
        self.routes[route.route] = ConstrainedXPCHandlerWithMessageWithoutReply(handler: handler)
    }
    
    /// Registers a route that has no message and expects a reply.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    /// - Throws: If this route has already been registered.
    public func registerRoute<R: Decodable>(_ route: XPCRouteWithoutMessageWithReply<R>,
                                            handler: @escaping () throws -> R) throws {
        if self.routes.keys.contains(route.route) {
            throw XPCError.routeAlreadyRegistered(route.route.pathComponents)
        }
        
        self.routes[route.route] = ConstrainedXPCHandlerWithoutMessageWithReply(handler: handler)
    }
    
    /// Registers a route that has a message and expects a reply.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    /// - Throws: If this route has already been registered.
    public func registerRoute<M: Decodable, R: Encodable>(_ route: XPCRouteWithMessageWithReply<M, R>,
                                                          handler: @escaping (M) throws -> R) throws {
        if self.routes.keys.contains(route.route) {
            throw XPCError.routeAlreadyRegistered(route.route.pathComponents)
        }
        
        self.routes[route.route] = ConstrainedXPCHandlerWithMessageWithReply(handler: handler)
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
        if xpc_get_type(event) == XPC_TYPE_DICTIONARY {
            if self.messageAcceptor.acceptMessage(connection: connection, message: event) {
                var reply = xpc_dictionary_create_reply(event)
                do {
                    try handleMessage(connection: connection, message: event, reply: &reply)
                } catch let error as XPCError {
                    self.errorHandler?(error)
                    self.replyWithErrorIfPossible(error, connection: connection, reply: &reply)
                } catch let error as DecodingError {
                    let wrappedError = XPCError.decodingError(String(describing: error))
                    self.errorHandler?(wrappedError)
                    self.replyWithErrorIfPossible(wrappedError, connection: connection, reply: &reply)
                }  catch let error as EncodingError {
                    let wrappedError = XPCError.encodingError(String(describing: error))
                    self.errorHandler?(wrappedError)
                    self.replyWithErrorIfPossible(wrappedError, connection: connection, reply: &reply)
                } catch {
                    let wrappedError = XPCError.other(String(describing: error))
                    self.errorHandler?(wrappedError)
                    self.replyWithErrorIfPossible(wrappedError, connection: connection, reply: &reply)
                }
            } else {
                self.errorHandler?(XPCError.insecure)
            }
        } else if xpc_equal(event, XPC_ERROR_CONNECTION_INVALID) {
            self.errorHandler?(XPCError.connectionInvalid)
        } else if xpc_equal(event, XPC_ERROR_CONNECTION_INTERRUPTED) {
            self.errorHandler?(XPCError.connectionInterrupted)
        } else if xpc_equal(event, XPC_ERROR_TERMINATION_IMMINENT) {
            self.errorHandler?(XPCError.terminationImminent)
        } else {
            self.errorHandler?(XPCError.unknown)
        }
    }
    
    private func handleMessage(connection: xpc_connection_t, message: xpc_object_t, reply: inout xpc_object_t?) throws {
        let request = try Request(dictionary: message)
        guard let handler = self.routes[request.route] else {
            throw XPCError.routeNotRegistered(request.route.pathComponents)
        }
        try handler.handle(request: request, reply: &reply)
        
        // If a dictionary reply exists, then the message expects a reply to be sent back
        if let reply = reply {
            xpc_connection_send_message(connection, reply)
        }
    }
    
    private func replyWithErrorIfPossible(_ error: XPCError, connection: xpc_connection_t, reply: inout xpc_object_t?) {
        if var reply = reply {
            do {
                try Response.encodeError(error, intoReply: &reply)
                xpc_connection_send_message(connection, reply)
            } catch {
                // If encoding the error fails, then there's no way to proceed
            }
        }
    }

	// MARK: Abstract methods
    
    /// Begins processing requests received by this XPC server and never returns.
    ///
    /// If this server is for an XPC Service, how the server will run is determined by the info property list's
    /// [`RunLoopType`](https://developer.apple.com/documentation/bundleresources/information_property_list/xpcservice/runlooptype?changes=l_3).
    /// If no value is specified, `dispatch_main` is the default. If `dispatch_main` is specified or defaulted to, it is a programming error to call this function
    /// from any thread besides the main thread.
    ///
    /// If this server is for a Mach service or is an anonymous server, it is always a programming error to call this function from any thread besides the main thread.
    public func startAndBlock() -> Never {
        fatalError("Abstract Method")
    }
    
    internal var messageAcceptor: MessageAcceptor {
        fatalError("Abstract Property")
    }

    public var serviceName: String? {
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
    /// Use an endpoint to create connections to this server
    var endpoint: XPCServerEndpoint { get }
    
    // Internal implementation note: `endpoint` is part of the `NonBlockingServer` protocol instead of `XPCServer` as
    // `XPCServiceServer` can't have an endpoint created for it.
    
    // From a technical perspective this is because endpoints are only created from connection listeners, which an XPC
    // Service doesn't expose (incoming connections are simply passed to the handler provided to `xpc_main(...)`. From
    // a security point of view, it makes sense that it's not possible to create an endpoint for an XPC Service because
    // they're designed to only allow communication between the main app and .xpc bundles contained within the same
    // main app's bundle. As such there's no valid use case for creating such an endpoint.
}

// MARK: handler function wrappers

// These wrappers perform type erasure via their implemented protocols while internally maintaining type constraints
// This makes it possible to create heterogenous collections of them

fileprivate protocol XPCHandler {
    func handle(request: Request, reply: inout xpc_object_t?) throws
}

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
        if replyType == nil, reply != nil {
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

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithoutReply: XPCHandler {
    let handler: () throws -> Void
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        try checkMatchesRequest(request, reply: &reply, messageType: nil, replyType: nil)
        try self.handler()
    }
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithoutReply<M: Decodable>: XPCHandler {
    let handler: (M) throws -> Void
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        try checkMatchesRequest(request, reply: &reply, messageType: M.self, replyType: nil)
        let decodedMessage = try request.decodePayload(asType: M.self)
        try self.handler(decodedMessage)
    }
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithReply<R: Encodable>: XPCHandler {
    let handler: () throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        try checkMatchesRequest(request, reply: &reply, messageType: nil, replyType: R.self)
        let payload = try self.handler()
        try Response.encodePayload(payload, intoReply: &reply!)
    }
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithReply<M: Decodable, R: Encodable>: XPCHandler {
    let handler: (M) throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        try checkMatchesRequest(request, reply: &reply, messageType: M.self, replyType: R.self)
        let decodedMessage = try request.decodePayload(asType: M.self)
        let payload = try self.handler(decodedMessage)
        try Response.encodePayload(payload, intoReply: &reply!)
    }
}
