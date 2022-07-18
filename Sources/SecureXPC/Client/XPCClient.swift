//
//  XPCClient.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// An XPC client to make requests and receive responses from an ``XPCServer``.
///
/// ### Retrieving a Client For a Service
/// There are two different types of services you can communicate with using this client: XPC services and XPC Mach services. If you are uncertain which type of
/// service you're using, it's likely an XPC service.
///
/// #### XPC services
/// These are helper tools which ship as part of your app and only your app can communicate with.
///
/// The name of the service must be specified when retrieving a client to talk to your XPC service; this is always the bundle identifier for the service:
/// ```swift
/// let client = XPCClient.forXPCService(named: "com.example.myapp.service")
/// ```
///
/// #### XPC Mach services
/// XPC Mach services are frequently provided by:
/// - Helper tools installed with
/// [  `SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless)
/// - Login items enabled with
/// [`SMLoginItemSetEnabled`](https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled)
/// - Launch Agents
/// - Launch Daemons
///
/// The name of the service must be specified when retrieving a client to talk to your XPC Mach service:
/// ```swift
/// let client = XPCClient.forXPCMachService(named: "com.example.service")
/// ```
///
/// ## Retrieving a Client For an Anonymous Server
/// Clients can also be created from an ``XPCServerEndpoint`` which is the only way to create a client for an anonymous server:
/// ```swift
/// let server = XPCServer.makeAnonymous()
/// let client = XPCClient.forEndpoint(server.endpoint)
/// ```
///
/// ### Sending Requests with Async
/// Once a client has been retrieved, sending a request is as simple as invoking `send` with a route:
/// ```swift
/// let resetRoute = XPCRoute.named("reset")
/// try await client.send(to: resetRoute)
/// ```
///
/// If the client needs to receive information back from the server, a route with a reply type must be used:
/// ```swift
/// let currentRoute = XPCRoute.named("config", "current")
///                            .withReplyType(Config.self)
/// let config = try await client.send(to: currentRoute)
/// ```
///
/// Routes can also require a message be included in the request:
/// ```swift
/// let updateRoute = XPCRoute.named("config", "update")
///                           .withMessageType(Config.self)
///                           .withReplyType(Config.self)
/// let config = <# create Config instance #>
/// let updatedConfig = try await client.sendMessage(config, to: updateRoute)
/// ```
///
/// Alternatively, routes can return an asynchronous sequence of replies:
/// ```swift
/// let changesRoute = XPCRoute.named("config", "changes")
///                            .withSequentialReplyType(Config.self)
/// let configStream = client.send(to: changesRoute)
/// for try await latestConfig in configStream {
///     <#do something with Config instance #>
/// }
/// ```
/// Whether a sequence ever finishes is determined by the implementation registered with the server or if a client side error occurs during decoding.
///
/// ### Sending Requests with Closures
/// Closure-based versions of these functions also exist to provide support for macOS 10.14 and earlier:
/// ```swift
/// let updateRoute = XPCRoute.named("config", "update")
///                           .withMessageType(Config.self)
///                           .withReplyType(Config.self)
/// let config = <# create Config instance #>
/// client.sendMessage(config, to: updateRoute, withResponse: { response in
///     switch response {
///          case .success(let reply):
///              <# use the reply #>
///          case .failure(let error):
///              <# handle the error #>
///     }
/// })
/// ```
///
/// For these closure-based functions, the ``XPCClient/XPCResponseHandler`` provided as the `withResponse` or `onCompletion` parameter is
/// always passed a [`Result`](https://developer.apple.com/documentation/swift/result) with the `Success` value matching the route's
/// `replyType` (or `Void` if there is no reply) and a `Failure` of type ``XPCError``. If an error was thrown by the server while handling the request, it will
/// be provided as an ``XPCError`` on failure.
///
/// Closure-based functions also exist for sequential responses:
///```swift
/// let changesRoute = XPCRoute.named("config", "changes")
///                            .withSequentialReplyType(Config.self)
/// let configStream = client.send(to: changesRoute, withSequentialResponse: { response in
///     switch response {
///         case .success(let reply):
///             <# use the reply #>
///         case .failure(let error):
///             <# handle the error #>
///         case .finished:
///             <# maybe do something on completion #>
///     }
/// })
/// ```
///
/// For these closure-based functions that use ``XPCClient/XPCSequentialResponseHandler``, they will be passed a ``SequentialResult`` with the
/// `Success` value matching the route's `sequentialReplyType`. If the sequence fails then a `Failure` of type ``XPCError`` will be passed and this
/// will terminate the sequence. If the sequence completed successfully then ``SequentialResult/finished`` will be passed. Whether a sequence ever
/// completes is determined by the implementation registered with the server or if a client side error occurs during decoding.
///
/// ## Topics
/// ### Retrieving a Client
/// - ``forXPCService(named:)``
/// - ``forMachService(named:withServerRequirement:)``
/// - ``forEndpoint(_:withServerRequirement:)``
/// ### Sending Requests with Async
/// - ``send(to:)-5b1ar``
/// - ``send(to:)-18k1k``
/// - ``send(to:)-7rreg``
/// - ``sendMessage(_:to:)-9t25c``
/// - ``sendMessage(_:to:)-68i1h``
/// - ``sendMessage(_:to:)-5vdys``
/// ### Sending Requests with Closures
/// - ``send(to:onCompletion:)``
/// - ``send(to:withResponse:)``
/// - ``send(to:withSequentialResponse:)``
/// - ``sendMessage(_:to:onCompletion:)``
/// - ``sendMessage(_:to:withResponse:)``
/// - ``sendMessage(_:to:withSequentialResponse:)``
/// ### Receiving Responses with Closures
/// - ``XPCResponseHandler``
/// - ``XPCSequentialResponseHandler``
/// ### Client Information
/// - ``connectionDescriptor``
/// ### Server Information
/// - ``serverIdentity``
/// - ``serverIdentity(_:)``
public class XPCClient {
    
    private let inProgressSequentialReplies = InProgressSequentialReplies()
    private let serverRequirement: XPCServerRequirement
    private var connection: xpc_connection_t? = nil
    
    internal init(serverRequirement: XPCServerRequirement) {
        self.serverRequirement = serverRequirement
    }
    
    // MARK: Abstract methods & properties
    
    /// The type of connection created by this client.
    public var connectionDescriptor: XPCConnectionDescriptor {
        fatalError("Abstract Property")
    }

    /// Creates and returns a connection for the service represented by this client.
    internal func createConnection() -> xpc_connection_t {
        fatalError("Abstract Method")
    }
    
    // MARK: Send
    
    /// Receives the result of a request.
    ///
    /// The result is either an instance of the reply type on success or an ``XPCError`` on failure.
    public typealias XPCResponseHandler<R> = (Result<R, XPCError>) -> Void
    
    /// Receives the sequential result of a request.
    ///
    /// The result is an instance of the sequential reply type on success, an ``XPCError`` on failure, or
    /// ``SequentialResult/finished`` if the sequence has been completed.
    public typealias XPCSequentialResponseHandler<S> = (SequentialResult<S, XPCError>) -> Void
    
    /// Sends a request with no message that does not receive a reply.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this request.
    ///   - handler: An optionally provided closure to receive a response upon successful completion or error.
    public func send(
        to route: XPCRouteWithoutMessageWithoutReply,
        onCompletion handler: XPCResponseHandler<Void>?
    ) {
        if let handler = handler {
            do {
                let request = try Request(route: route.route)
                sendRequest(request, withResponse: handler)
            } catch {
                handler(.failure(XPCError.asXPCError(error: error)))
            }
        } else {
            if let encoded = try? Request(route: route.route).dictionary {
                self.withConnection { result in
                    switch result {
                        case .success(let connection):
                            xpc_connection_send_message(connection, encoded)
                        case .failure(_):
                            break
                    }
                }
            }
        }
    }
    
    /// Sends a request with no message that does not receive a reply.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this request.
    @available(macOS 10.15.0, *)
    public func send(
        to route: XPCRouteWithoutMessageWithoutReply
    ) async throws {
        try await withUnsafeThrowingContinuation { continuation in
            send(to: route) { response in
                self.resumeContinuation(continuation, unwrappingResponse: response)
            }
        }
    }
    
    /// Sends a request with a message that does not receive a reply.
    ///
    /// - Parameters:
    ///   - message: Message to be included in the request.
    ///   - route: The server route which will handle this request.
    ///   - handler: An optionally provided closure to receive a response upon successful completion or error.
    public func sendMessage<M: Encodable>(
        _ message: M,
        to route: XPCRouteWithMessageWithoutReply<M>,
        onCompletion handler: XPCResponseHandler<Void>?
    ) {
        if let handler = handler {
            do {
                let request = try Request(route: route.route, payload: message)
                sendRequest(request, withResponse: handler)
            } catch {
                handler(.failure(XPCError.asXPCError(error: error)))
            }
        } else {
            if let encoded = try? Request(route: route.route, payload: message).dictionary {
                self.withConnection { result in
                    switch result {
                        case .success(let connection):
                            xpc_connection_send_message(connection, encoded)
                        case .failure(_):
                            break
                    }
                }
            }
        }
    }
    
    /// Sends a request with message that does not receive a reply.
    ///
    /// - Parameters:
    ///   - message: Message to be included in the request.
    ///   - route: The server route which will handle this request.
    @available(macOS 10.15.0, *)
    public func sendMessage<M: Encodable>(
        _ message: M,
        to route: XPCRouteWithMessageWithoutReply<M>
    ) async throws {
        try await withUnsafeThrowingContinuation { continuation in
            sendMessage(message, to: route) { response in
                self.resumeContinuation(continuation, unwrappingResponse: response)
            }
        }
    }
    
    /// Sends a request with no message and provides the response as either a reply on success or an error on failure.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this request.
    ///   - handler: A closure to receive the request's response.
    public func send<R: Decodable>(
        to route: XPCRouteWithoutMessageWithReply<R>,
        withResponse handler: @escaping XPCResponseHandler<R>
    ) {
        do {
            let request = try Request(route: route.route)
            sendRequest(request, withResponse: handler)
        } catch {
            handler(.failure(XPCError.asXPCError(error: error)))
        }
    }
    
    /// Sends a request with no message and receives a reply.
    ///
    /// - Parameters:
    ///    - route: The server route which will handle this request.
    @available(macOS 10.15.0, *)
    public func send<R: Decodable>(
        to route: XPCRouteWithoutMessageWithReply<R>
    ) async throws -> R {
        try await withUnsafeThrowingContinuation { continuation in
            send(to: route) { response in
                self.resumeContinuation(continuation, unwrappingResponse: response)
            }
        }
    }
    
    /// Sends a request with a message and provides the response as either a reply on success or an error on failure.
    ///
    /// - Parameters:
    ///    - message: Message to be included in the request.
    ///    - route: The server route which will handle this request.
    ///    - handler: A closure to receive the request's response.
    public func sendMessage<M: Encodable, R: Decodable>(
        _ message: M,
        to route: XPCRouteWithMessageWithReply<M, R>,
        withResponse handler: @escaping XPCResponseHandler<R>
    ) {
        do {
            let request = try Request(route: route.route, payload: message)
            sendRequest(request, withResponse: handler)
        } catch {
            handler(.failure(XPCError.asXPCError(error: error)))
        }
    }
    
    /// Sends a request with a message that receives a reply.
    ///
    /// - Parameters:
    ///    - message: Message to be included in the request.
    ///    - route: The server route which will handle this request.
    @available(macOS 10.15.0, *)
    public func sendMessage<M: Encodable, R: Decodable>(
        _ message: M,
        to route: XPCRouteWithMessageWithReply<M, R>
    ) async throws -> R {
        try await withUnsafeThrowingContinuation { continuation in
            sendMessage(message, to: route) { response in
                self.resumeContinuation(continuation, unwrappingResponse: response)
            }
        }
    }
    
    /// Sends a request with no message and provides sequential responses to the provided closure.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this request.
    ///   - handler: A closure to receive zero or more of request's responses.
    public func send<S: Decodable>(
        to route: XPCRouteWithoutMessageWithSequentialReply<S>,
        withSequentialResponse handler: @escaping XPCSequentialResponseHandler<S>
    ) {
        do {
            let request = try Request(route: route.route)
            sendRequest(request, handler: handler)
        } catch {
            handler(.failure(XPCError.asXPCError(error: error)))
        }
    }
    
    /// Sends a request with no message and asynchronously populates the returned stream with responses.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this request.
    @available(macOS 10.15.0, *)
    public func send<S: Decodable>(
        to route: XPCRouteWithoutMessageWithSequentialReply<S>
    ) -> AsyncThrowingStream<S, Error> {
        AsyncThrowingStream<S, Error> { continuation in
            self.send(to: route) { result in
                self.populateAsyncThrowingStreamContinuation(continuation, result: result)
            }
        }
    }
    
    /// Sends a request with a message and provides sequential response to the provided closure.
    ///
    /// - Parameters:
    ///   - message: Message to be included in the request.
    ///   - route: The server route which will handle this request.
    ///   - handler: A closure to receive zero or more of request's responses.
    public func sendMessage<M: Encodable, S: Decodable>(
        _ message: M,
        to route: XPCRouteWithMessageWithSequentialReply<M, S>,
        withSequentialResponse handler: @escaping XPCSequentialResponseHandler<S>
    ) {
        do {
            let request = try Request(route: route.route, payload: message)
            sendRequest(request, handler: handler)
        } catch {
            handler(.failure(XPCError.asXPCError(error: error)))
        }
    }
    
    /// Sends a request with a message and asynchronously populates the returned stream with responses.
    ///
    /// - Parameters:
    ///   - message: Message to be included in the request.
    ///   - route: The server route which will handle this request.
    @available(macOS 10.15.0, *)
    public func sendMessage<M: Encodable, S: Decodable>(
        _ message: M,
        to route: XPCRouteWithMessageWithSequentialReply<M, S>
    ) -> AsyncThrowingStream<S, Error> {
        AsyncThrowingStream<S, Error> { continuation in
            self.sendMessage(message, to: route) { result in
                self.populateAsyncThrowingStreamContinuation(continuation, result: result)
            }
        }
    }
    
    // MARK: Send (private internals)
    
    /// Does the actual work of sending an XPC request which receives a response.
    private func sendRequest<R: Decodable>(
        _ request: Request,
        withResponse handler: @escaping XPCResponseHandler<R>
    ) {
        self.withConnection { connectionResult in
            switch connectionResult {
                case .success(let connection):
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
                                } else if R.self == EmptyResponse.self { // Special case for expected empty response
                                    result = .success(EmptyResponse.instance as! R)
                                } else {
                                    result = .failure(.internalFailure(description: """
                                    Response is not empty nor does it contain a payload or error
                                    """))
                                }
                            } catch {
                                result = .failure(XPCError.asXPCError(error: error))
                            }
                        } else {
                            result = .failure(XPCError.fromXPCObject(reply))
                        }
                        self.handleError(event: reply)
                        handler(result)
                    }
                case .failure(let error):
                    handler(.failure(error))
                    return
            }
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
    
    /// Does the actual work of sending an XPC request which receives zero or more sequential responses.
    private func sendRequest<S: Decodable>(_ request: Request, handler: @escaping XPCSequentialResponseHandler<S>) {
        self.withConnection { connectionResult in
            switch connectionResult {
                case .success(let connection):
                    let internalHandler = InternalXPCSequentialResponseHandlerImpl(request: request, handler: handler)
                    self.inProgressSequentialReplies.registerHandler(internalHandler, forRequest: request)
                    
                    // Sending with reply means the server ought to be kept alive until the reply is sent back
                    // From https://developer.apple.com/documentation/xpc/1505586-xpc_transaction_begin:
                    //    A service with no outstanding transactions may automatically exit due to inactivity as
                    //    determined by the system... If a reply message is created, the transaction will end when the
                    //    reply message is sent or released.
                    xpc_connection_send_message_with_reply(connection, request.dictionary, nil) { reply in
                        // From xpc_connection_send_message documentation:
                        //   If this API is used to send a message that is in reply to another message, there is no
                        //   guarantee of ordering between the invocations of the connection's event handler and the
                        //   reply handler for that message, even if they are targeted to the same queue.
                        //
                        // The net effect of this is we can't do much with the reply such as terminating the sequence or
                        // deregistering the handler because this reply will sometimes arrive before some of the
                        // out-of-band sends from the server to client are received. (This was attempted and it caused
                        // unit tests to fail non-deterministically.)
                        //
                        // But if this is an internal XPC error (for example because the server shut down), we can use
                        // this to update the connection's state.
                        if xpc_get_type(reply) == XPC_TYPE_ERROR {
                            self.handleError(event: reply)
                        }
                    }
                case .failure(let error):
                    handler(.failure(XPCError.asXPCError(error: error)))
                    return
            }
        }
    }
    
    /// Populates the continuation while unwrapping any underlying errors thrown by a server's handler.
    @available(macOS 10.15.0, *)
    private func populateAsyncThrowingStreamContinuation<S: Decodable>(
        _ continuation: AsyncThrowingStream<S, Error>.Continuation,
        result: SequentialResult<S, XPCError>
    ) {
        switch result {
            case .success(let value):
                continuation.yield(value)
            case .failure(let error):
                if case .handlerError(let handlerError) = error,
                   case .available(let underlyingError) = handlerError.underlyingError {
                    continuation.finish(throwing: underlyingError)
                } else {
                    continuation.finish(throwing: error)
                }
                continuation.finish(throwing: error)
            case .finished:
                continuation.finish(throwing: nil)
        }
    }
    
    // Provides a connection, doing so asynchronously when a new connection needs to be created. A connection is only
    // provided if it meets this client's server requirement.
    private func withConnection(_ handler: @escaping (Result<xpc_connection_t, XPCError>) -> Void) {
        // The connection is set to nil when certain error conditions are encountered, see `handleError(...)`
        if let connection = self.connection {
            handler(.success(connection))
            return
        }
        
        // The connection needs to be started (resumed) so that we can retrieve the server's identity
        let connection = self.createConnection()
        xpc_connection_set_event_handler(connection, self.handleEvent(event:))
        xpc_connection_resume(connection)
        
        self.serverIdentity(connection: connection) { response in
            switch response {
                case .success(let serverIdentity):
                    guard self.serverRequirement.trustServer(serverIdentity) else {
                        handler(.failure(.insecure))
                        return
                    }
                    self.connection = connection
                    handler(.success(connection))
                case .failure(let error):
                    xpc_connection_cancel(connection)
                    handler(.failure(error))
            }
        }
    }
    
    // MARK: Incoming event handling
    
    private func handleEvent(event: xpc_object_t) {
        if xpc_get_type(event) == XPC_TYPE_DICTIONARY {
            self.inProgressSequentialReplies.handleMessage(event)
        } else if xpc_get_type(event) == XPC_TYPE_ERROR {
            self.handleError(event: event)
        }
    }

    private func handleError(event: xpc_object_t) {
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
    
    // MARK: Server identity
    
    /// A representation of the server's running program.
    ///
    /// The returned ``XPCServerIdentity``'s information is provided by macOS itself and cannot be misrepresented (intentionally or otherwise) by the server.
    ///
    /// > Note: Accessing this property involves cross-process communication with the server and is therefore subject to all of the same error conditions as making
    /// a `send` or `sendMessage` call.
    @available(macOS 10.15.0, *)
    public var serverIdentity: XPCServerIdentity {
        get async throws {
            try await withUnsafeThrowingContinuation { continuation in
                self.serverIdentity { response in
                    continuation.resume(with: response)
                }
            }
        }
    }
    
    /// Provides a representation of the server's running program to the handler.
    ///
    /// The provided ``XPCServerIdentity``'s information comes from macOS itself and cannot be misrepresented (intentionally or otherwise) by the server.
    ///
    /// > Note: Calling this function involves cross-process communication with the server and is therefore subject to all of the same error conditions as making a
    /// `send` or `sendMessage` call.
    public func serverIdentity(_ handler: @escaping XPCResponseHandler<XPCServerIdentity>) {
        self.withConnection { connectionResult in
            switch connectionResult {
                case .success(let connection):
                    self.serverIdentity(connection: connection, handler: handler)
                case .failure(let error):
                    handler(.failure(error))
                    return
            }
        }
    }
    
    // Private implementation that has a connection passed in. This is needed because `withConnection` needs to call
    // this function when creating a new connection, while the public version calls `withConnection` which would result
    // in infinite recursion between these two functions.
    private func serverIdentity(
        connection: xpc_connection_t,
        handler: @escaping XPCResponseHandler<XPCServerIdentity>
    ) {
        // Create request
        let request: Request
        do {
            request = try Request(route: PackageInternalRoutes.noopRoute.route)
        } catch {
            handler(.failure(XPCError.asXPCError(error: error)))
            return
        }
        
        // Async send the request over XPC
        xpc_connection_send_message_with_reply(connection, request.dictionary, nil) { reply in
            if xpc_get_type(reply) == XPC_TYPE_ERROR {
                handler(.failure(XPCError.fromXPCObject(reply)))
                return
            }
            
            // It doesn't matter what the reply actually contains, we just need it to determine server identity
            guard let code = SecCodeCreateWithXPCConnection(connection, andMessage: reply) else {
                handler(.failure(XPCError.internalFailure(description: "Unable to get server's SecCode")))
                return
            }
            let serverIdentity = XPCServerIdentity(code: code,
                                                   effectiveUserID: xpc_connection_get_euid(connection),
                                                   effectiveGroupID: xpc_connection_get_egid(connection),
                                                   processID: xpc_connection_get_pid(connection))
            handler(.success(serverIdentity))
        }
    }
}

// MARK: public factories

// Contains all of the `static` code that provides the entry points to retrieving an `XPCClient` instance.

extension XPCClient {
    
    // Note: It's intentional that the naming and documentation for these entry points are ambiguous as to whether a
    // new client is actually created or not; the wording "retrieved" and and "retrieval" is used instead of ever saying
    // "created" (or similar). While in the current implementation a new client instance is always created, that could
    // be changed in the future to return a cached one without any change to the API nor inconsistency with its
    // documented behavior.
    
    /// Provides a client to communicate with an XPC service.
    ///
    /// An XPC service is a helper tool which ships as part of your app and only your app can communicate with.
    ///
    /// In order for this client to be able to communicate with the XPC service, the service itself must retrieve and configure an ``XPCServer`` by calling
    /// ``XPCServer/forThisXPCService()``.
    ///
    /// > Note: It is a fatal error to provide a name for an XPC service which does not correspond to an XPC service contained within this bundle.
    ///
    /// While there are no _explicit_ security requirements for the server, macOS enforces that the XPC service can only exist within this bundle and therefore is
    /// expected to be trustworthy.
    ///
    /// - Parameters:
    ///   - serviceName: The bundle identifier (`CFBundleIdentifier`)  of the XPC service.
    /// - Returns: A client configured to communicate with the named service.
    public static func forXPCService(named serviceName: String) -> XPCClient {
        // This isn't necessary to do, as it's not harmful to create a client for a service which doesn't exist, but
        // this makes it easier for API users to catch mistakes sooner; a likely one would be a typo in the service name
        guard bundledXPCServiceIdentifiers.contains(serviceName) else {
            fatalError("""
            There is no bundled XPC service named \(serviceName)
            Available XPC service names are:
            \(bundledXPCServiceIdentifiers.joined(separator: "\n"))
            """)
        }
        
        return XPCServiceClient(xpcServiceName: serviceName, serverRequirement: .alwaysAccepting)
    }
    
    /// The `CFBundleIdentifier` values for every `.xpc` file in the `Contents/XPCServices` of this app (if it exists).
    private static let bundledXPCServiceIdentifiers: Set<String> = {
        let servicesDir = Bundle.main.bundleURL.appendingPathComponent("Contents")
                                               .appendingPathComponent("XPCServices")
        guard let servicesContents = try? FileManager.default.contentsOfDirectory(atPath: servicesDir.path) else {
            return []
        }
        
        let xpcBundleNames = servicesContents.filter { $0.hasSuffix(".xpc") }
        let xpcBundles = xpcBundleNames.compactMap { Bundle(url: servicesDir.appendingPathComponent($0)) }
        let xpcBundleIDs = xpcBundles.compactMap { $0.infoDictionary?[kCFBundleIdentifierKey as String] as? String }
        
        return Set<String>(xpcBundleIDs)
    }()
    
    /// Provides a client to communicate with an XPC Mach service.
    ///
    /// XPC Mach services include:
    /// - Helper tools installed with
    /// [  `SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless)
    /// - Login items enabled with
    /// [`SMLoginItemSetEnabled`](https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled)
    /// - Launch Agents
    /// - Launch Daemons
    ///
    /// In order for this client to be able to communicate with the XPC Mach service, the service itself must retrieve and configure an ``XPCServer`` by calling
    /// ``XPCServer/forMachService(withCriteria:)``.
    ///
    /// > Note: Client retrieval always succeeds regardless of whether or not the XPC Mach service exists.
    ///
    /// - Parameters:
    ///    - machServiceName: For most Mach services the name is specified with the `MachServices` launchd property list entry (or similar); however, for
    ///                       login items the name is its bundle identifier (`CFBundleIdentifier`).
    ///    - serverRequirement: The requirement the server needs to meet in order for this client to communicate with it. By default this client will trust a
    ///                         server with the same team identifier so long as this client has a team identifier; if this client does not have a team identifier
    ///                         then any server will be trusted.
    /// - Returns: A client configured to communicate with the named service.
    public static func forMachService(
        named machServiceName: String,
        withServerRequirement serverRequirement: XPCServerRequirement = .sameTeamIdentifierIfPresent
    ) -> XPCClient {
        XPCMachClient(machServiceName: machServiceName, serverRequirement: serverRequirement)
    }

    /// Provides a client to communicate with the server corresponding to the provided endpoint.
    ///
    /// A server's endpoint is accesible via ``XPCServer/endpoint``. The endpoint can be sent across an XPC connection.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint with which to establish a connection.
    ///   - serverRequirement: The requirement the server needs to meet in order for this client to communicate with it. By default only a server in the same
    ///                        process will be trusted which will always work a server retrieved with ``XPCServer/makeAnonymous()``. However, for
    ///                        any server that is running outside of this process, a non-default requirement such as
    ///                        ``XPCServerRequirement/sameTeamIdentifier`` will need to be provided.
    /// - Returns: A client configured to communicate with the provided endpoint.
    public static func forEndpoint(
        _ endpoint: XPCServerEndpoint,
        withServerRequirement serverRequirement: XPCServerRequirement = .sameProcess
    ) -> XPCClient {
        XPCEndpointClient(endpoint: endpoint, serverRequirement: serverRequirement)
    }
}

// MARK: Sequential reply helpers

/// This allows for type erasure
fileprivate protocol InternalXPCSequentialResponseHandler {
    var route: XPCRoute { get }
    func handleResponse(_ response: Response)
}

fileprivate class InternalXPCSequentialResponseHandlerImpl<S: Decodable>: InternalXPCSequentialResponseHandler {
    let route: XPCRoute
    private var failedToDecode = false
    private let handler: XPCClient.XPCSequentialResponseHandler<S>
    
    /// All responses for a given request need to be run serially in the order they were received and we don't want deserialization or the user's handler closure to
    /// block anything else from happening.
    private let serialQueue: DispatchQueue
    
    fileprivate init(request: Request, handler: @escaping XPCClient.XPCSequentialResponseHandler<S>) {
        self.route = request.route
        self.handler = handler
        self.serialQueue = DispatchQueue(label: "response-handler-\(request.requestID)")
    }
    
    fileprivate func handleResponse(_ response: Response) {
        self.serialQueue.async {
            if self.failedToDecode {
                return
            }
            
            do {
                if response.containsPayload {
                    self.handler(.success(try response.decodePayload(asType: S.self)))
                } else if response.containsError {
                    self.handler(.failure(try response.decodeError()))
                } else {
                    self.handler(.finished)
                }
            } catch {
                // If we failed to decode then we need to terminate the sequence; however, the server won't know this
                // happened. (Even if we were to inform the server it'd only be an optimization because the server
                // could've already sent more replies in the interim.) We need to now ignore any future replies to
                // prevent adding to the now terminated sequence. This requirement comes from how iterating over an
                // async sequence works where if a call to `next()` throws then the iteration terminates. This is
                // reflected in the documentation for `AsyncThrowingStream`:
                //     In contrast to AsyncStream, this type can throw an error from the awaited next(), which
                //     terminates the stream with the thrown error.
                //
                // While in theory we don't have to enforce this for the closure-based implementation, in principle and
                // practice we want the closure and async implementations to be as consistent as possible.
                self.handler(.failure(XPCError.asXPCError(error: error)))
                self.failedToDecode = true
            }
        }
    }
}

/// Encapsulates all in progress requests which were made to the server that could still receive more out-of-band message sends which need to be reassociated
/// with their requests in order to become reply sequences.
fileprivate class InProgressSequentialReplies {
    /// Mapping of requestIDs to handlers.
    private var handlers = [UUID : InternalXPCSequentialResponseHandler]()
    /// This queue is used to serialize access to the above dictionary.
    private let serialQueue = DispatchQueue(label: String(describing: InProgressSequentialReplies.self))
    
    func registerHandler(_ handler: InternalXPCSequentialResponseHandler, forRequest request: Request) {
        serialQueue.async {
            self.handlers[request.requestID] = handler
        }
    }
    
    func handleMessage(_ message: xpc_object_t) {
        serialQueue.async {
            let response: Response
            do {
                let requestID = try Response.decodeRequestID(dictionary: message)
                guard let route = self.handlers[requestID]?.route else {
                    return
                }
                response = try Response(dictionary: message, route: route)
            } catch {
                // In theory these could be reported to some sort of error handler set on the client, but it's an
                // intentional choice to not introduce that additional conceptual complexity for API users because in
                // all other cases errors are associated with the specific send/sendMessage call.
                return
            }
            
            // Retrieve the handler, removing it if the sequence has finished or errored out
            let handler: InternalXPCSequentialResponseHandler?
            if response.containsPayload {
                handler = self.handlers[response.requestID]
            } else if response.containsError {
                handler = self.handlers.removeValue(forKey: response.requestID)
            } else { // Finished
                handler = self.handlers.removeValue(forKey: response.requestID)
            }
            guard let handler = handler else {
                fatalError("Sequential result was received for an unregistered requestID: \(response.requestID)")
            }
            
            handler.handleResponse(response)
        }
    }
}
