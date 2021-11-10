//
//  XPCServer.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// An XPC server to receive calls from and send responses to an ``XPCClient``.
///
/// ### Creating a Server
/// If the program creating this server is a helper tool which meets
/// [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) requirements then in most
/// cases creating a server is as easy as
/// ```swift
/// let server = try XPCServer.forThisBlessedHelperTool()
/// ```
/// See ``XPCServer/forThisBlessedHelperTool()`` for the exact requirements which need to be met.
///
/// #### Other Mach Services
///
/// Otherwise you'll need to manually initialize a server by specifying the name of the XPC Mach Service and providing the security requirements for connecting
/// clients. See ``forMachService(named:clientRequirements:)`` for an example and details.
///
/// **Requirement Checking**
///
/// On macOS 11 and later, requirement checking uses publicly documented APIs. On older versions of macOS, the private undocumented API
/// `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)` will be used; if for some reason the function is unavailable
/// then no messages will be accepted. When messages are not accepted, if the ``XPCServer/errorHandler`` is set then it is called
/// with ``XPCError/insecure``.
///
/// #### XPC Services
///
/// TODO
///
/// ### Registering & Handling Routes
/// Once a server instance has been created, one or more routes should be registered with it. This is done by calling one of the `registerRoute` functions and
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
/// Once all of the routes are registered, the server must be told to start processing requests:
/// ```swift
/// server.start()
/// ```
///
/// This function replicates default [`xpc_main()`](https://developer.apple.com/documentation/xpc/1505740-xpc_main) behavior by calling
/// [`dispatchMain()`](https://developer.apple.com/documentation/dispatch/1452860-dispatchmain) and never returning.
///
/// ## Topics
/// ### Creating a Server
/// - ``forThisBlessedHelperTool()``
/// - ``forMachService(named:clientRequirements:)``
/// - ``forThisXPCService()``
///
/// ### Registering Routes
/// - ``registerRoute(_:handler:)-1jw9d``
/// - ``registerRoute(_:handler:)-4fxv0``
/// - ``registerRoute(_:handler:)-4ttqe``
/// - ``registerRoute(_:handler:)-9a0x9``
///
/// ### Starting a Server
/// - ``start()``
///
/// ### Error Handling
/// - ``errorHandler``
public class XPCServer {

	// MARK: Public factories

	/// Creates a server that accepts requests from clients which meet the security requirements.
	///
	/// Because many processes on the system can talk to an XPC Mach Service, when creating a server it is required that you specifiy the security requirements
	/// of any connecting clients:
	/// ```swift
	/// let reqString = """identifier "com.example.AuthorizedClient" and certificate leaf[subject.OU] = "4L0ZG128MM" """
	/// var requirement: SecRequirement?
	/// if SecRequirementCreateWithString(reqString as CFString,
	///                                   SecCSFlags(),
	///                                   &requirement) == errSecSuccess,
	///   let requirement = requirement {
	///    let server = XPCMachServer(machServiceName: "com.example.service",
	///                               clientRequirements: [requirement])
	///
	///    <# configure and start server #>
	/// }
	/// ```
	///
	/// > Important: No requests will be processed until ``start()`` is called.
	///
	/// - Parameters:
	///   - machServiceName: The name of the mach service this server should bind to. This name must be present in this program's launchd property list's
	///                      `MachServices` entry.
	///   - clientRequirements: If a request is received from a client, it will only be processed if it meets one (or more) of these security requirements.
	public static func forMachService(
		named machServiceName: String,
		clientRequirements: [SecRequirement]
	) -> XPCServer {
		XPCMachServer(machServiceName: machServiceName, clientRequirements: clientRequirements)
	}

	/// Initializes a server for a helper tool that meets
	/// [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) requirements.
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
	/// > Important: No requests will be processed until ``start()`` is called.
	///
	/// - Returns: A server instance initialized with the embedded property list entries.
	public static func forThisBlessedHelperTool() throws -> XPCServer {
		try XPCMachServer._forThisBlessedHelperTool()
	}

	public static func forThisXPCService() -> XPCServer {
		XPCServiceServer.service
	}

	// MARK: Implementation

    /// If set, errors encountered will be sent to this handler.
    public var errorHandler: ((XPCError) -> Void)?
    
    // Routes
    private var routesWithoutMessageWithReply = [XPCRoute : XPCHandlerWithoutMessageWithReply]()
    private var routesWithMessageWithReply = [XPCRoute : XPCHandlerWithMessageWithReply]()
    private var routesWithoutMessageWithoutReply = [XPCRoute : XPCHandlerWithoutMessageWithoutReply]()
    private var routesWithMessageWithoutReply = [XPCRoute : XPCHandlerWithMessageWithoutReply]()
    
    /// Registers a route that has no message and can't receive a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths and types.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute(_ route: XPCRouteWithoutMessageWithoutReply,
                              handler: @escaping () throws -> Void) {
        let handlerWrapper = ConstrainedXPCHandlerWithoutMessageWithoutReply(handler: handler)
        self.routesWithoutMessageWithoutReply[route.route] = handlerWrapper
    }
    
    /// Registers a route that has a message and can't receive a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths and types.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<M: Decodable>(_ route: XPCRouteWithMessageWithoutReply<M>,
                                            handler: @escaping (M) throws -> Void) {
        let handlerWrapper = ConstrainedXPCHandlerWithMessageWithoutReply(handler: handler)
        self.routesWithMessageWithoutReply[route.route] = handlerWrapper
    }
    
    /// Registers a route that has no message and expects a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths and types.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<R: Decodable>(_ route: XPCRouteWithoutMessageWithReply<R>,
                                            handler: @escaping () throws -> R) {
        let handlerWrapper = ConstrainedXPCHandlerWithoutMessageWithReply(handler: handler)
        self.routesWithoutMessageWithReply[route.route] = handlerWrapper
    }
    
    /// Registers a route that has a message and expects a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths and types.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<M: Decodable, R: Encodable>(_ route: XPCRouteWithMessageWithReply<M, R>,
                                                          handler: @escaping (M) throws -> R) {
        let handlerWrapper = ConstrainedXPCHandlerWithMessageWithReply(handler: handler)
        self.routesWithMessageWithReply[route.route] = handlerWrapper
    }
    
    internal func handleEvent(connection: xpc_connection_t, event: xpc_object_t) {
        if xpc_get_type(event) == XPC_TYPE_DICTIONARY {
            if self.acceptMessage(connection: connection, message: event) {
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

        // If a dictionary reply exists, then the message expects a reply
        if var reply = reply {
            if request.containsPayload {
                if let handler = self.routesWithMessageWithReply[request.route] {
                    try handler.handle(request: request, reply: &reply)
                    xpc_connection_send_message(connection, reply)
                } else {
                    throw XPCError.routeNotRegistered(String(describing: request.route))
                }
            } else {
                if let handler = self.routesWithoutMessageWithReply[request.route] {
                    try handler.handle(reply: &reply)
                    xpc_connection_send_message(connection, reply)
                } else {
                    throw XPCError.routeNotRegistered(String(describing: request.route))
                }
            }
        } else { // Otherwise the message can't receive a reply
            if request.containsPayload {
                if let handler = self.routesWithMessageWithoutReply[request.route] {
                    try handler.handle(request: request)
                } else {
                    throw XPCError.routeNotRegistered(String(describing: request.route))
                }
            } else {
                if let handler = self.routesWithoutMessageWithoutReply[request.route] {
                    try handler.handle()
                } else {
                    throw XPCError.routeNotRegistered(String(describing: request.route))
                }
            }
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

	/// Begins processing requests received by this XPC server.
	///
	/// This function replicates [`xpc_main()`](https://developer.apple.com/documentation/xpc/1505740-xpc_main) behavior by never
	/// returning.
	public func start() -> Never {
		fatalError("Abstract Method")
	}

	/// Determines whether the message should be accepted.
	///
	/// This is determined using the client requirements provided to this server upon initialization.
	/// - Parameters:
	///   - connection: The connection the message was sent over.
	///   - message: The message.
	/// - Returns: whether the message can be accepted
	internal func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
		fatalError("Abstract Method")
	}
}

// MARK: handler function wrappers

// These wrappers perform type erasure via their implemented protocols while internally maintaining type constraints
// This makes it possible to create heterogenous collections of them

fileprivate protocol XPCHandlerWithoutMessageWithoutReply {
    func handle() throws -> Void
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithoutReply: XPCHandlerWithoutMessageWithoutReply {
    let handler: () throws -> Void
    
    func handle() throws {
        try self.handler()
    }
}

fileprivate protocol XPCHandlerWithMessageWithoutReply {
    func handle(request: Request) throws -> Void
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithoutReply<M: Decodable>: XPCHandlerWithMessageWithoutReply {
    let handler: (M) throws -> Void
    
    func handle(request: Request) throws {
        let decodedMessage = try request.decodePayload(asType: M.self)
        try self.handler(decodedMessage)
    }
}

fileprivate protocol XPCHandlerWithoutMessageWithReply {
    func handle(reply: inout xpc_object_t) throws
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithReply<R: Encodable>: XPCHandlerWithoutMessageWithReply {
    let handler: () throws -> R
    
    func handle(reply: inout xpc_object_t) throws {
        let payload = try self.handler()
        try Response.encodePayload(payload, intoReply: &reply)
    }
}

fileprivate protocol XPCHandlerWithMessageWithReply {
    func handle(request: Request, reply: inout xpc_object_t) throws
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithReply<M: Decodable, R: Encodable>: XPCHandlerWithMessageWithReply {
    let handler: (M) throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t) throws {
        let decodedMessage = try request.decodePayload(asType: M.self)
        let payload = try self.handler(decodedMessage)
        try Response.encodePayload(payload, intoReply: &reply)
    }
}
