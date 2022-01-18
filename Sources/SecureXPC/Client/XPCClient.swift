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
/// There are two different types of services you can communicate with using this client: XPC Services and XPC Mach services. If you are uncertain which
/// type of service you're using, it's likely it's an XPC Service.
///
/// **XPC Services**
///
/// These are helper tools which ship as part of your app and only your app can communicate with.
///
/// The name of the service must be specified when retrieving a client to talk to your XPC Service; this is always the bundle identifier for the service:
/// ```swift
/// let client = XPCClient.forXPCService(named: "com.example.myapp.service")
/// ```
///
/// The service itself must create and configure an ``XPCServer`` by calling ``XPCServer/forThisXPCService()`` in order for this client to be able to
/// communicate with it.
///
/// **XPC Mach services**
///
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
/// ### Calling Routes
/// Once a client has been retrieved, calling a route is as simple as invoking `send` with a route:
/// ```swift
/// let resetRoute = XPCRouteWithoutMessageWithoutReply("reset")
/// try client.send(route: resetRoute)
/// ```
///
/// While a client may throw an error when sending, this will only occur due to an encoding error. If after successfully encoding the message fails to send or is not
/// received by a server, no error will be raised due to how XPC is designed. If it is important for your code to have confirmation of receipt then a route with a reply
/// should be used:
/// ```swift
/// let resetRoute = XPCRouteWithoutMessageWithReply("reset", replyType: Bool.self)
/// try client.send(route: resetRoute, withReply: { result in
///     switch result {
///          case let .success(reply):
///              <# use the reply #>
///          case let .failure(error):
///              <# handle the error #>
///     }
/// })
/// ```
///
/// The ``XPCClient/XPCReplyHandler`` provided to the `withReply` parameter is always passed a
/// [`Result`](https://developer.apple.com/documentation/swift/result) with the `Success` value matching the route's `replyType` and a
///  `Failure` of type ``XPCError``. If an error was thrown by the server while handling the request, it will be provided as an ``XPCError`` on failure.
///
/// When calling a route, there is also the option to include a message:
/// ```swift
/// let updateConfigRoute = XPCRouteWithMessageWithReply("update", "config",
///                                                      messageType: Config.self,
///                                                      replyType: Config.self)
/// let config = <# create Config instance #>
/// client.sendMessage(config, route: updateConfigRoute, withReply: {
///     <# process reply #>
/// })
/// ```
///
/// In this example a custom `Config` type that conforms to `Codable` was used as both the message and reply types. A hypothetical implementation could
/// consist of the desired configuration update being sent as a message and the server replying with the actual configuration after attempting to apply the changes.
///
/// ## Topics
/// ### Retrieving a Client
/// - ``forXPCService(named:)``
/// - ``forMachService(named:)``
/// ### Calling Routes
/// - ``send(route:)``
/// - ``send(route:withReply:)``
/// - ``sendMessage(_:route:)``
/// - ``sendMessage(_:route:withReply:)``
/// ### Receiving Replies
/// - ``XPCReplyHandler``
public class XPCClient {
    
    // MARK: Public factories
    
    /// Provides a client to communicate with an XPC Service.
    ///
    /// An XPC Service is a helper tool which ships as part of your app and only your app can communicate with.
    ///
    /// In order for this client to be able to communicate with the XPC Service, the service itself must retrieve and configure an ``XPCServer`` by calling
    /// ``XPCServer/forThisXPCService()``.
    ///
    /// > Note: Client creation always succeeds regardless of whether the XPC Service actually exists.
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
                let encoded = try Request(route: route.route).dictionary
                sendWithResponse(encoded: encoded, withResponse: handler)
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
                let encoded = try Request(route: route.route, payload: message).dictionary
                sendWithResponse(encoded: encoded, withResponse: handler)
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
    
    /// Sends with no message and provides the response as either a reply on success or an error on failure.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this.
    ///   - withResponse: A function or closure to receive the response.
    public func send<R: Decodable>(route: XPCRouteWithoutMessageWithReply<R>,
                                   withReply handler: @escaping XPCResponseHandler<R>) {
        do {
            let encoded = try Request(route: route.route).dictionary
            sendWithResponse(encoded: encoded, withResponse: handler)
        } catch {
            handler(.failure(.encodingError(String(describing: error))))
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
            let encoded = try Request(route: route.route, payload: message).dictionary
            sendWithResponse(encoded: encoded, withResponse: handler)
        } catch {
            handler(.failure(.encodingError(String(describing: error))))
        }
    }
    
    /// Does the actual work of sending an XPC message which receives a response.
    private func sendWithResponse<R: Decodable>(encoded: xpc_object_t,
                                                withResponse handler: @escaping XPCResponseHandler<R>) {
        // Get the connection or inform the handler of failure and return
        var connection: xpc_connection_t?
        do {
            connection = try getConnection()
        } catch {
            if let error = error as? XPCError {
                handler(.failure(error))
            } else {
                handler(.failure(.unknown))
            }
        }
        guard let connection = connection else {
            return
        }
        
        // Async send the message over XPC
        xpc_connection_send_message_with_reply(connection, encoded, nil) { reply in
            let result: Result<R, XPCError>
            if xpc_get_type(reply) == XPC_TYPE_DICTIONARY {
                do {
                    let response = try Response(dictionary: reply)
                    if response.containsPayload {
                        result = .success(try response.decodePayload(asType: R.self))
                    } else if response.containsError {
                        result = .failure(try response.decodeError())
                    } else if R.self == EmptyResponse.self { // Special case for when an empty response is expected
                        result = .success(EmptyResponse.instance as! R)
                    } else {
                        result = .failure(.unknown)
                    }
                } catch let error as XPCError  {
                    result = .failure(error)
                } catch {
                    result = .failure(.unknown)
                }
            } else if xpc_equal(reply, XPC_ERROR_CONNECTION_INVALID) {
                result = .failure(.connectionInvalid)
            } else if xpc_equal(reply, XPC_ERROR_CONNECTION_INTERRUPTED) {
                result = .failure(.connectionInterrupted)
            } else { // Unexpected
                result = .failure(.unknown)
            }
            self.handleConnectionErrors(event: reply)
            handler(result)
        }
    }
    
    /// Wrapper that handles responses without a payload since `Void` is not `Decodable`
    private func sendWithResponse(encoded: xpc_object_t, withResponse handler: @escaping XPCResponseHandler<Void>) {
        self.sendWithResponse(encoded: encoded) { (response: Result<EmptyResponse, XPCError>) -> Void in
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
            // While Apple's documentation is technically correct, it's misleading in the case of an anonymous
            // connection where there is no service. Because there is no service, there is nothing to be relaunched
            // on-demand. The connection might technically still be alive, but resending a message will *not* work.
            //
            // By setting the connection to `nil` when there is no service (indicated by no service name), anonymous
            // clients can throw a useful specific error when `createConnection()` is called.
            if self.serviceName == nil {
                self.connection = nil
            }
        }
        
        // XPC_ERROR_TERMINATION_IMMINENT is not applicable to the client side of a connection
    }

    // MARK: Abstract methods


    public var serviceName: String? {
        fatalError("Abstract Property")
    }

    /// Creates and returns a connection for the service represented by this client.
    internal func createConnection() throws -> xpc_connection_t {
        fatalError("Abstract Method")
    }
}
