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
/// There are two different types of services you can communicate with using this client: XPC services and XPC Mach services. In most cases you do not need to
/// know which type you'll be communicating with as this will be auto-detected, so creating a client only requires providing its name:
/// ```swift
/// let client = XPCClient.forService(named: "com.example.myapp.service")
/// ```
///
/// It is possible to explicitly specify the type of client which will be returned and in some uncommon cases this will is required. See ``ServiceType`` for details.
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
/// Closure-based functions also existing for sequential responses:
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
/// - ``forService(named:ofType:)``
/// - ``ServiceType``
/// - ``forEndpoint(_:)``
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
public class XPCClient {
    
    // MARK: Public factories
    
    /// The type of service an ``XPCClient`` should be retrieved for.
    public enum ServiceType {
        /// Auto-detects what type of client to retrieve for the name provided to ``XPCClient/forService(named:ofType:)``.
        ///
        /// This is accomplished by finding the names (`CFBundleIdentifier`s) for each of the XPC services bundled with this app. If the name provided
        /// to `forService(named:ofType:)` belongs to one of the XPC services then a client will be created to communicate with it. Otherwise, a client
        /// will be created to communicate with an XPC Mach service.
        ///
        /// If there is a Mach service you need to communicate with that has the same name as a bundled XPC service, explicitly retrieve the client as such
        /// by passing in ``machService`` as the type.
        case autoDetect
        /// Ensures the client returned by ``XPCClient/forService(named:ofType:)`` communicates with an XPC Mach service with the provided
        /// name.
        ///
        /// Launch Agents, Launch Daemons, helper tools installed with
        /// [  `SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless),
        /// and login items installed with
        /// [`SMLoginItemSetEnabled`](https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled)
        /// can all optionally communicate over XPC by using Mach services.
        case machService
        /// Ensures the client returned by ``XPCClient/forService(named:ofType:)`` communicates with an XPC service with the provided name.
        ///
        /// XPC services are helper tools which ship as part of your app and only your app can communicate with.
        ///
        /// It is a programming error to specify this type and provide `forService(named:ofType:)` a name which does not correspond to an XPC service
        /// bundled with the calling app. You may find this behavior helpful for debugging purposes.
        case xpcService
    }
    
    /// Provides a client to communicate with a service.
    ///
    /// In order for this client to be able to communicate with the service, the service itself must retrieve and configure an ``XPCServer`` by calling
    /// ``XPCServer/forThisProcess(ofType:)``.
    ///
    /// > Note: Client creation can succeed regardless of whether the service actually exists.
    ///
    /// - Parameters:
    ///   - named: The `CFBundleIdentifier` of the XPC service or the name of the XPC Mach service. For most Mach services the name is specified
    ///            with the `MachServices` launchd property list entry; however, for login items the name is its`CFBundleIdentifier`.
    ///   - ofType: There are multiple different types of XPC clients and normally you do not need to concern yourself with this. However, if you are trying to
    ///             create a client for an XPC Mach service *and* you have an XPC service with a CFBundleIdentifier value that's the same as the name of
    ///             that Mach service, then you must call this function and explicitly set the type to ``ServiceType/machService``. This is because auto
    ///             detection will always choose the XPC service if one exists with the provided name.
    /// - Returns: A client configured to communicate with the named service.
    public static func forService(named serviceName: String, ofType type: ServiceType = .autoDetect) -> XPCClient {
        switch type {
            case .autoDetect:
                if bundledXPCServiceIdentifiers.contains(serviceName) {
                    return XPCServiceClient(xpcServiceName: serviceName)
                } else {
                    return XPCMachClient(machServiceName: serviceName)
                }
            case .xpcService:
                guard bundledXPCServiceIdentifiers.contains(serviceName) else {
                    let message = "There is no bundled XPC service with name \(serviceName)\n" +
                                  "Available XPC service names are:\n" +
                                  bundledXPCServiceIdentifiers.joined(separator: "\n")
                    fatalError(message)
                }
                
                return XPCServiceClient(xpcServiceName: serviceName)
            case .machService:
                return XPCMachClient(machServiceName: serviceName)
        }
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

    /// Provides a client to communicate with the server corresponding to the provided endpoint.
    ///
    /// A server's endpoint is accesible via ``XPCServer/endpoint``. The endpoint can be sent across an XPC connection.
	public static func forEndpoint(_ endpoint: XPCServerEndpoint) -> XPCClient {
        let connection = xpc_connection_create_from_endpoint(endpoint.endpoint)

        xpc_connection_set_event_handler(connection, { (event: xpc_object_t) in
            fatalError("It should be impossible for this connection to receive an event.")
        })
        xpc_connection_resume(connection)

        switch endpoint.connectionDescriptor {
            case .anonymous:
                return XPCAnonymousClient(connection: connection, connectionDescriptor: .anonymous)
            // XPCServiceServer creates an anonymous listener connection in order to provide an endpoint, so an
            // anonymous client needs to be created to connect to it, but we want to preserve the connection descriptor
            case .xpcService(_):
                return XPCAnonymousClient(connection: connection, connectionDescriptor: endpoint.connectionDescriptor)
            case .machService(name: let name):
                return XPCMachClient(machServiceName: name, connection: connection)
        }
    }

    // MARK: Implementation

    private let inProgressSequentialReplies = InProgressSequentialReplies()
    
    private var connection: xpc_connection_t? = nil
    
    internal init(connection: xpc_connection_t? = nil) {
        self.connection = connection
        if let connection = connection {
            xpc_connection_set_event_handler(connection, self.handleEvent(event:))
        }
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
            if let encoded = try? Request(route: route.route).dictionary,
               let connection = try? getConnection() {
                xpc_connection_send_message(connection, encoded)
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
            if let encoded = try? Request(route: route.route, payload: message).dictionary,
               let connection = try? getConnection() {
                xpc_connection_send_message(connection, encoded)
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
                        result = .failure(.internalFailure(description: "Response is not empty nor does it contain a " +
                                                                        "payload or error"))
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
        // Get the connection or inform the handler of failure and return
        let connection: xpc_connection_t
        do {
            connection = try getConnection()
        } catch {
            handler(.failure(XPCError.asXPCError(error: error)))
            return
        }
        
        let internalHandler = InternalXPCSequentialResponseHandlerImpl(request: request, handler: handler)
        self.inProgressSequentialReplies.registerHandler(internalHandler, forRequest: request)
        
        // Sending with reply means the server ought to be kept alive until the reply is sent back
        // From https://developer.apple.com/documentation/xpc/1505586-xpc_transaction_begin:
        //    A service with no outstanding transactions may automatically exit due to inactivity as determined by the
        //    system... If a reply message is created, the transaction will end when the reply message is sent or
        //    released.
        xpc_connection_send_message_with_reply(connection, request.dictionary, nil) { reply in
            // From xpc_connection_send_message documentation:
            //   If this API is used to send a message that is in reply to another message, there is no guarantee of
            //   ordering between the invocations of the connection's event handler and the reply handler for that
            //   message, even if they are targeted to the same queue.
            //
            // The net effect of this is we can't do much with the reply such as terminating the sequence or
            // deregistering the handler because this reply will sometimes arrive before some of the out-of-band sends
            // from the server to client are received. (This was attempted and it caused unit tests to fail
            // non-deterministically.)
            //
            // But if this is an internal XPC error (for example because the server shut down), we can use this to
            // update the connection's state.
            if xpc_get_type(reply) == XPC_TYPE_ERROR {
                self.handleError(event: reply)
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

    private func getConnection() throws -> xpc_connection_t {
        if let existingConnection = self.connection { return existingConnection }

        let newConnection = try self.createConnection()
        self.connection = newConnection

        xpc_connection_set_event_handler(newConnection, self.handleEvent(event:))
        xpc_connection_resume(newConnection)

        return newConnection
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

    // MARK: Abstract methods & properties
    
    /// The type of connection created by this client.
    public var connectionDescriptor: XPCConnectionDescriptor {
        fatalError("Abstract Property")
    }

    /// Creates and returns a connection for the service represented by this client.
    internal func createConnection() throws -> xpc_connection_t {
        fatalError("Abstract Method")
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
