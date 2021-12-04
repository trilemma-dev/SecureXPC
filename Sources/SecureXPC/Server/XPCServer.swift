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
/// Once all of the routes are registered, the server must be told to start processing requests:
/// ```swift
/// server.start()
/// ```
///
/// Internally this function calls [`dispatchMain()`](https://developer.apple.com/documentation/dispatch/1452860-dispatchmain) and never
/// returns.
///
/// ## Topics
/// ### Retrieving a Server
/// - ``forThisXPCService()`` 
/// - ``forThisBlessedHelperTool()``
/// - ``forThisMachService(named:clientRequirements:)``
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
    
    /// Provides a server for this XPC Service.
    ///
    /// For the provided server to function properly, the caller must be an XPC Service.
    ///
    /// > Important: No requests will be processed until ``start()`` is called.
    ///
    /// - Throws: ``XPCError/notXPCService`` if the caller is not an XPC Service.
    /// - Returns: A server instance configured for this XPC Service.
    public static func forThisXPCService() throws -> XPCServer {
        try XPCServiceServer._forThisXPCService()
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
    /// > Important: No requests will be processed until ``start()`` is called.
    ///
    /// - Throws: ``XPCError/misconfiguredBlessedHelperTool(_:)`` if the configuration does not match this function's requirements.
    /// - Returns: A server instance configured with the embedded property list entries.
    public static func forThisBlessedHelperTool() throws -> XPCServer {
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
    /// > Important: No requests will be processed until ``start()`` is called.
    ///
    /// - Parameters:
    ///   - named: The name of the mach service this server should bind to. This name must be present in the launchd property list's `MachServices` entry.
    ///   - clientRequirements: If a request is received from a client, it will only be processed if it meets one (or more) of these requirements.
    /// - Throws: ``XPCError/conflictingClientRequirements`` if a server for this named service has previously been retrieved with different client
    ///           requirements.
    public static func forThisMachService(
        named machServiceName: String,
        clientRequirements: [SecRequirement]
    ) throws -> XPCServer {
        try XPCMachServer.getXPCMachServer(named: machServiceName, clientRequirements: clientRequirements)
    }

    // MARK: Implementation

    /// If set, errors encountered will be sent to this handler.
    public var errorHandler: ((XPCError) -> Void)?
    
    // Routes
    private var routes = [XPCRoute : XPCHandler]()
    
    /// Registers a route that has no message and can't receive a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute(_ route: XPCRouteWithoutMessageWithoutReply,
                              handler: @escaping () throws -> Void) {
        self.routes[route.route] = ConstrainedXPCHandlerWithoutMessageWithoutReply(handler: handler)
    }
    
    /// Registers a route that has a message and can't receive a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<M: Decodable>(_ route: XPCRouteWithMessageWithoutReply<M>,
                                            handler: @escaping (M) throws -> Void) {
        self.routes[route.route] = ConstrainedXPCHandlerWithMessageWithoutReply(handler: handler)
    }
    
    /// Registers a route that has no message and expects a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<R: Decodable>(_ route: XPCRouteWithoutMessageWithReply<R>,
                                            handler: @escaping () throws -> R) {
        self.routes[route.route] = ConstrainedXPCHandlerWithoutMessageWithReply(handler: handler)
    }
    
    /// Registers a route that has a message and expects a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<M: Decodable, R: Encodable>(_ route: XPCRouteWithMessageWithReply<M, R>,
                                                          handler: @escaping (M) throws -> R) {
        self.routes[route.route] = ConstrainedXPCHandlerWithMessageWithReply(handler: handler)
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
        if let handler = self.routes[request.route] {
            try handler.handle(request: request, reply: &reply)
            
            // If a dictionary reply exists, then the message expects a reply to be sent back
            if let reply = reply {
                xpc_connection_send_message(connection, reply)
            }
        } else {
            throw XPCError.routeNotRegistered(String(describing: request.route))
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
    /// Internally this function calls [`dispatchMain()`](https://developer.apple.com/documentation/dispatch/1452860-dispatchmain) and
    /// never returns.
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

fileprivate protocol XPCHandler {
    func handle(request: Request, reply: inout xpc_object_t?) throws
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithoutReply: XPCHandler {
    let handler: () throws -> Void
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        if request.containsPayload {
            throw XPCError.routeMismatch("Incoming request for route \(request.route.pathComponents) contained a " +
                                         "message of type \(String(describing: request.route.messageType)), but the " +
                                         "handler registered with the server does not have a message parameter.")
        }
        if reply != nil {
            throw XPCError.routeMismatch("Incoming request for route \(request.route.pathComponents) expects a reply " +
                                         "of type \(String(describing: request.route.replyType)), but the handler " +
                                         "registered with the server has no return value.")
        }
        
        try self.handler()
    }
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithoutReply<M: Decodable>: XPCHandler {
    let handler: (M) throws -> Void
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        if !request.containsPayload {
            throw XPCError.routeMismatch("Incoming request for route \(request.route.pathComponents) did not contain " +
                                         "a message, but the handler registered with the server has a message " +
                                         "parameter of type \(M.self).")
        }
        if reply != nil {
            throw XPCError.routeMismatch("Incoming request for route \(request.route.pathComponents) expects a reply " +
                                         "of type \(String(describing: request.route.replyType)), but the handler " +
                                         "registered with the server has no return value.")
        }
        
        let decodedMessage = try request.decodePayload(asType: M.self)
        try self.handler(decodedMessage)
    }
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithReply<R: Encodable>: XPCHandler {
    let handler: () throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        if request.containsPayload {
            throw XPCError.routeMismatch("Incoming request for route \(request.route.pathComponents) contained a " +
                                         "message of type \(String(describing: request.route.messageType)), but the " +
                                         "handler registered with the server does not have a message parameter.")
        }
        
        if var reply = reply {
            let payload = try self.handler()
            try Response.encodePayload(payload, intoReply: &reply)
        } else {
            throw XPCError.routeMismatch("Incoming request for route \(request.route.pathComponents) does not expect " +
                                         "a reply, but the handler registered with the server has a return value of " +
                                         "type \(R.self).")
        }
    }
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithReply<M: Decodable, R: Encodable>: XPCHandler {
    let handler: (M) throws -> R
    
    func handle(request: Request, reply: inout xpc_object_t?) throws {
        if !request.containsPayload {
            throw XPCError.routeMismatch("Incoming request for route \(request.route.pathComponents) did not contain " +
                                         "a message, but the handler registered with the server has a message " +
                                         "parameter of type \(M.self).")
        }
        
        if var reply = reply {
            let decodedMessage = try request.decodePayload(asType: M.self)
            let payload = try self.handler(decodedMessage)
            try Response.encodePayload(payload, intoReply: &reply)
        } else {
            throw XPCError.routeMismatch("Incoming request for route \(request.route.pathComponents) does not expect " +
                                         "a reply, but the handler registered with the server has a return value of " +
                                         "type \(R.self).")
        }
    }
}
