//
//  XPCClient.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// An XPC client to make requests and receive responses from an ``XPCServer``.
///
/// ### Retrieving a Client
/// There are two different types of services you can communicate with using this client: XPC services and XPC Mach services. If you are uncertain which
/// type of service you're using, it's likely an XPC Service.
///
/// Clients can also be created from an ``XPCServerEndpoint`` which is the only way to create a client for an anonymous server.
///
/// #### XPC services
/// These are helper tools which ship as part of your app and only your app can communicate with.
///
/// The name of the service must be specified when retrieving a client to talk to your XPC service; this is always the bundle identifier for the service:
/// ```swift
/// let client = XPCClient.forXPCService(named: "com.example.myapp.service")
/// ```
///
/// The service itself must create and configure an ``XPCServer`` by calling ``XPCServer/forThisXPCService()`` in order for this client to be able to
/// communicate with it.
///
/// #### XPC Mach services
/// Launch Agents, Launch Daemons, and helper tools installed with
/// [  `SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) can optionally communicate
/// over XPC by using Mach services.
///
/// The name of the service must be specified when retrieving a client; this must be a key in the `MachServices` entry of the tool's launchd property list:
/// ```swift
/// let client = XPCClient.forMachService(named: "com.example.service")
/// ```
/// The tool itself must retrieve and configure an ``XPCServer`` by calling ``XPCServer/forThisMachService(named:clientRequirements:)`` or
/// ``XPCServer/forThisBlessedHelperTool()`` in order for this client to be able to communicate with it.
///
/// #### Endpoints
/// Clients can be created from server endpoints:
/// ```swift
/// let server = XPCServer.makeAnonymous()
/// let client = XPCClient.forEndpoint(server.endpoint)
/// ```
/// Server endpoints can also be sent across XPC connections.
///
/// ### Calling Routes
/// Once a client has been retrieved, calling a route is as simple as invoking `send` with a route:
/// ```swift
/// let resetRoute = XPCRoute.named("reset")
/// client.send(route: resetRoute, onCompletion: nil)
/// ```
///
/// If confirmation that the send was received is needed, then an `onCompletion` handler must be set:
/// ```swift
/// let resetRoute = XPCRoute.named("reset")
/// client.send(route: resetRoute, onCompletion: { response in
///     switch response {
///         case .success(_):
///             <# confirm success #>
///         case .failure(let error):
///             <# handle the error #>
///     }
/// })
/// ```
///
/// If the client needs to receive information back from the server, a route with a reply type must be used:
/// ```swift
/// let currentConfigRoute = XPCRoute.named("config", "current")
///                                  .withReplyType(Config.self)
/// client.send(route: currentConfigRoute, withResponse: { response in
///     switch response {
///          case .success(let reply):
///              <# use the reply #>
///          case .failure(let error):
///              <# handle the error #>
///     }
/// })
/// ```
///
/// When calling a route, there is also the option to include a message:
/// ```swift
/// let updateConfigRoute = XPCRoute.named("config", "update")
///                                 .withMessageType(Config.self)
///                                 .withReplyType(Config.self)
/// let config = <# create Config instance #>
/// client.sendMessage(config, route: updateConfigRoute, withResponse: {
///     <# process response #>
/// })
/// ```
///
/// The ``XPCClient/XPCResponseHandler`` provided to the `withResponse` or `onCompletion` parameter is always passed a
/// [`Result`](https://developer.apple.com/documentation/swift/result) with the `Success` value matching the route's `replyType` (or
/// `Void` if there is no reply) and a `Failure` of type ``XPCError``. If an error was thrown by the server while handling the request, it will be provided as an
/// ``XPCError`` on failure.
///
/// ### Calling Routes Async
/// While calling routes is always done asynchronously, on macOS 10.15 and later it is possible to call routes using `async`.
///
/// Calling a route with no message and no reply:
/// ```swift
/// let resetRoute = XPCRoute.named("reset")
/// try await client.send(route: resetRoute)
/// ```
///
/// Calling a route with a message and a reply:
/// ```swift
/// let updateConfigRoute = XPCRoute.named("config", "update")
///                                 .withMessageType(Config.self)
///                                 .withReplyType(Config.self)
/// let config = <# create Config instance #>
/// let newConfig = try await client.sendMessage(config, route: updateConfigRoute)
/// ```
///
/// ## Topics
/// ### Retrieving a Client
/// - ``forXPCService(named:)``
/// - ``forMachService(named:)``
/// - ``forEndpoint(_:)``
/// ### Calling Routes
/// - ``send(route:onCompletion:)``
/// - ``send(route:withResponse:)``
/// - ``sendMessage(_:route:onCompletion:)``
/// - ``sendMessage(_:route:withResponse:)``
/// ### Receiving Responses
/// - ``XPCResponseHandler``
/// ### Calling Routes Async
/// - ``send(route:)-2xpwh``
/// - ``send(route:)-72u0z``
/// - ``sendMessage(_:route:)-8jn0q``
/// - ``sendMessage(_:route:)-45tw9``
/// ### Client Information
/// - ``serviceName``
public class XPCClient {
    
    // MARK: Public factories
    
    /// Provides a client to communicate with an XPC service.
    ///
    /// An XPC service is a helper tool which ships as part of your app and only your app can communicate with.
    ///
    /// In order for this client to be able to communicate with the XPC service, the service itself must retrieve and configure an ``XPCServer`` by calling
    /// ``XPCServer/forThisXPCService()``.
    ///
    /// > Note: Client creation always succeeds regardless of whether the XPC service actually exists.
    ///
    /// - Parameters:
    ///   - named: The bundle identifier of the XPC Service.
    /// - Returns: A client configured to communicate with the named service.
    public static func forXPCService(named xpcServiceName: String) -> XPCClient {
        XPCServiceClient(xpcServiceName: xpcServiceName)
    }
    
    /// Provides a client to communicate with an XPC Mach service.
    ///
    /// XPC Mach services are often used by tools such as Launch Agents, Launch Daemons, and helper tools installed with
    /// [  `SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless).
    ///
    /// In order for this client to be able to communicate with the tool, the tool itself must retrieve and configure an ``XPCServer`` by calling
    /// ``XPCServer/forThisMachService(named:clientRequirements:)`` or ``XPCServer/forThisBlessedHelperTool()``.
    ///
    /// > Note: Client creation always succeeds regardless of whether the XPC Mach service actually exists.
    ///
    /// - Parameters:
    ///    - named: A key in the `MachServices` entry of the tool's launchd property list.
    /// - Returns: A client configured to communicate with the named service.
    public static func forMachService(named machServiceName: String) -> XPCClient {
        XPCMachClient(machServiceName: machServiceName)
    }

    /// Provides a client to communicate with the server corresponding to the provided endpoint.
    ///
    /// A server's endpoint is accesible via ``NonBlockingServer/endpoint``. The endpoint can be sent across an XPC connection.
	public static func forEndpoint(_ endpoint: XPCServerEndpoint) -> XPCClient {
        let connection = xpc_connection_create_from_endpoint(endpoint.endpoint)

        xpc_connection_set_event_handler(connection, { (event: xpc_object_t) in
            fatalError("It should be impossible for this connection to receive an event.")
        })
        xpc_connection_resume(connection)

        switch endpoint.serviceDescriptor {
        case .anonymous: return XPCAnonymousClient(connection: connection)
        case .xpcService(name: let name): return XPCServiceClient(xpcServiceName: name, connection: connection)
        case .machService(name: let name): return XPCMachClient(machServiceName: name, connection: connection)
        }
    }

    // MARK: Implementation

    private var connection: xpc_connection_t? = nil
    
    /// Creates a client which will attempt to send messages to the specified mach service.
    ///
    /// - Parameters:
    ///   - serviceName: The name of the XPC service; no validation is performed on this.
    internal init(connection: xpc_connection_t? = nil) {
        self.connection = connection
        if let connection = connection {
            xpc_connection_set_event_handler(connection, self.handleConnectionErrors(event:))
        }
    }
    
    // MARK: Send
    
    /// Receives the result of an XPC send. The result is either an instance of the reply type on success or an ``XPCError`` on failure.
    public typealias XPCResponseHandler<R> = (Result<R, XPCError>) -> Void
    
    /// Sends with no message and will not receive a reply.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this.
    ///   - onCompletion: An optionally provided function or closure to receive a response upon successful completion or error.
    public func send(route: XPCRouteWithoutMessageWithoutReply,
                     onCompletion handler: XPCResponseHandler<Void>?) {
        if let handler = handler {
            do {
                let request = try Request(route: route.route)
                sendRequest(request, withResponse: handler)
            } catch {
                handler(.failure(.encodingError(String(describing: error))))
            }
        } else {
            if let encoded = try? Request(route: route.route).dictionary,
               let connection = try? getConnection() {
                xpc_connection_send_message(connection, encoded)
            }
        }
    }
    
    /// Sends with no message and does not receive a reply.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this.
    @available(macOS 10.15.0, *)
    public func send(route: XPCRouteWithoutMessageWithoutReply) async throws {
        try await withUnsafeThrowingContinuation { continuation in
            send(route: route) { response in
                self.resumeContinuation(continuation, unwrappingResponse: response)
            }
        }
    }
    
    /// Sends a message which will not receive a reply.
    ///
    /// - Parameters:
    ///   - message: Message to be sent.
    ///   - route: The server route which should handle this message.
    ///   - onCompletion: An optionally provided function or closure to receive a response upon successful completion or error.
    public func sendMessage<M: Encodable>(_ message: M,
                                          route: XPCRouteWithMessageWithoutReply<M>,
                                          onCompletion handler: XPCResponseHandler<Void>?) {
        if let handler = handler {
            do {
                let request = try Request(route: route.route, payload: message)
                sendRequest(request, withResponse: handler)
            } catch {
                handler(.failure(.encodingError(String(describing: error))))
            }
        } else {
            if let encoded = try? Request(route: route.route, payload: message).dictionary,
               let connection = try? getConnection() {
                xpc_connection_send_message(connection, encoded)
            }
        }
    }
    
    /// Sends a message and does not receive a reply.
    ///
    /// - Parameters:
    ///    - route: The server route which should handle this message.
    @available(macOS 10.15.0, *)
    public func sendMessage<M: Encodable>(_ message: M, route: XPCRouteWithMessageWithoutReply<M>) async throws {
        try await withUnsafeThrowingContinuation { continuation in
            sendMessage(message, route: route) { response in
                self.resumeContinuation(continuation, unwrappingResponse: response)
            }
        }
    }
    
    /// Sends with no message and provides the response as either a reply on success or an error on failure.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this.
    ///   - withResponse: A function or closure to receive the response.
    public func send<R: Decodable>(route: XPCRouteWithoutMessageWithReply<R>,
                                   withResponse handler: @escaping XPCResponseHandler<R>) {
        do {
            let request = try Request(route: route.route)
            sendRequest(request, withResponse: handler)
        } catch {
            handler(.failure(.encodingError(String(describing: error))))
        }
    }
    
    /// Sends with no message and receives a reply.
    ///
    /// - Parameters:
    ///    - route: The server route which should handle this message.
    @available(macOS 10.15.0, *)
    public func send<R: Decodable>(route: XPCRouteWithoutMessageWithReply<R>) async throws -> R {
        try await withUnsafeThrowingContinuation { continuation in
            send(route: route) { response in
                self.resumeContinuation(continuation, unwrappingResponse: response)
            }
        }
    }
    
    /// Sends a message and provides the response as either a reply on success or an error on failure.
    ///
    /// - Parameters:
    ///    - message: Message to be sent.
    ///    - route: The server route which should handle this message.
    ///    - withResponse: A function or closure to receive the message's response.
    public func sendMessage<M: Encodable, R: Decodable>(_ message: M,
                                                        route: XPCRouteWithMessageWithReply<M, R>,
                                                        withResponse handler: @escaping XPCResponseHandler<R>) {
        do {
            let request = try Request(route: route.route, payload: message)
            sendRequest(request, withResponse: handler)
        } catch {
            handler(.failure(.encodingError(String(describing: error))))
        }
    }
    
    /// Sends a message which receives a reply.
    ///
    /// - Parameters:
    ///    - message: Message to be sent.
    ///    - route: The server route which should handle this message.
    @available(macOS 10.15.0, *)
    public func sendMessage<M: Encodable, R: Decodable>(_ message: M,
                                                        route: XPCRouteWithMessageWithReply<M, R>) async throws -> R {
        try await withUnsafeThrowingContinuation { continuation in
            sendMessage(message, route: route) { response in
                self.resumeContinuation(continuation, unwrappingResponse: response)
            }
        }
    }
    
    /// Does the actual work of sending an XPC message which receives a response.
    private func sendRequest<R: Decodable>(_ request: Request,
                                           withResponse handler: @escaping XPCResponseHandler<R>) {
        // Get the connection or inform the handler of failure and return
        let connection: xpc_connection_t
        do {
            connection = try getConnection()
        } catch {
            handler(.failure(XPCError.asXPCError(error: error)))
            return
        }
        
        // Async send the message over XPC
        xpc_connection_send_message_with_reply(connection, request.dictionary, nil) { reply in
            let result: Result<R, XPCError>
            if xpc_get_type(reply) == XPC_TYPE_DICTIONARY {
                do {
                    let response = try Response(dictionary: reply, route: request.route)
                    if response.containsPayload {
                        result = .success(try response.decodePayload(asType: R.self))
                    } else if response.containsError {
                        result = .failure(try response.decodeError())
                    } else if R.self == EmptyResponse.self { // Special case for when an empty response is expected
                        result = .success(EmptyResponse.instance as! R)
                    } else {
                        result = .failure(.unknown)
                    }
                } catch {
                    result = .failure(XPCError.asXPCError(error: error))
                }
            } else {
                result = .failure(XPCError.fromXPCObject(reply))
            }
            self.handleConnectionErrors(event: reply)
            handler(result)
        }
    }
    
    /// Wrapper that handles responses without a payload since `Void` is not `Decodable`
    private func sendRequest(_ request: Request, withResponse handler: @escaping XPCResponseHandler<Void>) {
        self.sendRequest(request) { (response: Result<EmptyResponse, XPCError>) -> Void in
            switch response {
                case .success(_):
                    handler(.success(()))
                case .failure(let error):
                    handler(.failure(error))
            }
        }
    }
    
    /// Represents an XPC call which does not contain a payload or error in the response
    fileprivate enum EmptyResponse: Decodable {
        case instance
    }
    
    /// Resumes the continuation while unwrapping any underlying errors thrown by a server's handler.
    @available(macOS 10.15, *)
    private func resumeContinuation<T>(_ contination: UnsafeContinuation<T, Error>,
                                       unwrappingResponse response: Result<T, XPCError>) {
        if case let .failure(error) = response,
           case let .handlerError(handlerError) = error,
           case let .available(underlyingError) = handlerError.underlyingError {
            contination.resume(throwing: underlyingError)
        } else {
            contination.resume(with: response)
        }
    }

    
    private func getConnection() throws -> xpc_connection_t {
        if let existingConnection = self.connection { return existingConnection }

        let newConnection = try self.createConnection()
        self.connection = newConnection

        xpc_connection_set_event_handler(newConnection, self.handleConnectionErrors(event:))
        xpc_connection_resume(newConnection)

        return newConnection
    }

    private func handleConnectionErrors(event: xpc_object_t) {
        if xpc_equal(event, XPC_ERROR_CONNECTION_INVALID) {
            // Paraphrasing from Apple documentation:
            //   If the named service provided could not be found in the XPC service namespace. The connection is
            //   useless and should be disposed of.
            //
            // While the underlying connection is useless, this client instance is *not* useless. A scenario we want to
            // support is:
            //  - API user creates a client
            //  - Attempts to send a message to a blessed helper tool
            //  - `XPCError.connectionInvalid` is thrown
            //  - Error is handled by installing the helper tool
            //  - Using the same client instance successfully sends a message to the now installed helper tool
            self.connection = nil
        } else if xpc_equal(event, XPC_ERROR_CONNECTION_INTERRUPTED) {
            // Apple documentation:
            //   Will be delivered to the connection’s event handler if the remote service exited. The connection is
            //   still live even in this case, and resending a message will cause the service to be launched on-demand.
            //
            // From observed behavior Apple's documentation is *not* correct. After the connection is interrupted the
            // subsequent call will result in XPC_ERROR_CONNECTION_INVALID and the service will not be relaunched. See
            // https://github.com/trilemma-dev/SecureXPC/issues/70 for more details and discussion.
            //
            // Additionally, in the case of an anonymous connection there is no service. Because there is no service,
            // there is nothing to be relaunched on-demand. The connection might technically still be alive, but
            // resending a message will *not* work.
            self.connection = nil
        }
        
        // XPC_ERROR_TERMINATION_IMMINENT is not applicable to the client side of a connection
    }

    // MARK: Abstract methods & properties

    /// The name of the service this client is configured to communicate with.
    ///
    /// If this is configured to talk to an anonymous server then there is no service and therefore the service name will always be `nil`.
    public var serviceName: String? {
        fatalError("Abstract Property")
    }

    /// Creates and returns a connection for the service represented by this client.
    internal func createConnection() throws -> xpc_connection_t {
        fatalError("Abstract Method")
    }
}
