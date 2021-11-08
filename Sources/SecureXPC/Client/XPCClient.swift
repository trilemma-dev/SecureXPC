//
//  XPCClient.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// An XPC Mach Services client to call and receive responses from ``XPCMachServer``.
///
/// ### Calling Routes
/// Calling a route is as simple creating a client and invoking `send` with a route:
/// ```swift
/// let client = XPCMachClient(machServiceName: "com.example.service")
/// let resetRoute = XPCRouteWithoutMessageWithoutReply("reset")
/// try client.send(route: resetRoute)
/// ```
///
/// While a client may throw an error when sending, this will only occur due to an encoding error. If after successfully encoding the message fails to send or is not
/// received by a server, no error will be raised due to how XPC is designed. If it is important for your code to have confirmation of receipt then a route with a reply
/// should be used:
/// ```swift
/// let client = XPCMachClient(machServiceName: "com.example.service")
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
/// The ``XPCMachClient/XPCReplyHandler`` provided to the `withReply` parameter is always passed a
/// [`Result`](https://developer.apple.com/documentation/swift/result) with the `Success` value matching the route's `replyType` and a
///  `Failure` of type ``XPCError``. If an error was thrown by the server while handling the request, it will be provided as an ``XPCError`` on failure.
///
/// When calling a route, there is also the option to include a message:
/// ```swift
/// let client = XPCMachClient(machServiceName: "com.example.service")
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
/// ### Creating a Client
/// - ``init(machServiceName:)``
/// ### Calling Routes
/// - ``send(route:)``
/// - ``send(route:withReply:)``
/// - ``sendMessage(_:route:)``
/// - ``sendMessage(_:route:withReply:)``
/// ### Receiving Replies
/// - ``XPCReplyHandler``
public class XPCClient {
	// MARK: Public factories

	public static func forMachService(named machServiceName: String) -> XPCClient {
		XPCMachClient(serviceName: machServiceName)
	}

	// MARK: Implementation

    internal let serviceName: String
    
    /// Creates a client which will attempt to send messages to the specified mach service.
    ///
    /// - Parameters:
    ///   - machServiceName: The name of the XPC mach service; no validation is performed on this.
    internal init(serviceName: String) {
        self.serviceName = serviceName
    }
    
    /// Receives the result of an XPC send. The result is either an instance of the reply type on success or an ``XPCError`` on failure.
    public typealias XPCReplyHandler<R> = (Result<R, XPCError>) -> Void
    
    /// Sends with no message and will not receive a reply.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this.
    /// - Throws: If unable to encode the route. No error will be thrown if communication with the server fails.
    public func send(route: XPCRouteWithoutMessageWithoutReply) throws {
        let encoded = try Request(route: route.route).dictionary
        xpc_connection_send_message(createConnection(), encoded)
    }
    
    /// Sends a message which will not receive a response.
    ///
    /// - Parameters:
    ///    - message: Message to be sent.
    ///    - route: The server route which should handle this message.
    /// - Throws: If unable to encode the message or route. No error will be thrown if communication with the server fails.
    public func sendMessage<M: Encodable>(_ message: M, route: XPCRouteWithMessageWithoutReply<M>) throws {
        let encoded = try Request(route: route.route, payload: message).dictionary
        xpc_connection_send_message(createConnection(), encoded)
    }
    
    /// Sends with no message and provides the reply as either a message on success or an error on failure.
    ///
    /// - Parameters:
    ///   - route: The server route which will handle this.
    ///   - withReply: A function or closure to receive the reply.
    /// - Throws: If unable to encode the route. No error will be thrown if communication with the server fails.
    public func send<R: Decodable>(route: XPCRouteWithoutMessageWithReply<R>,
                                   withReply reply: @escaping XPCReplyHandler<R>) throws {
        let encoded = try Request(route: route.route).dictionary
        sendWithReply(encoded: encoded, withReply: reply)
    }
    
    /// Sends a message and provides the reply as either a message on success or an error on failure.
    ///
    /// - Parameters:
    ///    - message: Message to be sent.
    ///    - route: The server route which should handle this message.
    ///    - withReply: A function or closure to receive the message's reply.
    /// - Throws: If unable to encode the message or route. No error will be thrown if communication with the server fails.
    public func sendMessage<M: Encodable, R: Decodable>(_ message: M,
                                                        route: XPCRouteWithMessageWithReply<M, R>,
                                                        withReply reply: @escaping XPCReplyHandler<R>) throws {
        let encoded = try Request(route: route.route, payload: message).dictionary
        sendWithReply(encoded: encoded, withReply: reply)
    }
    
    /// Does the actual work of sending an XPC message which receives a reply.
    private func sendWithReply<R: Decodable>(encoded: xpc_object_t,
                                             withReply reply: @escaping XPCReplyHandler<R>) {
        xpc_connection_send_message_with_reply(createConnection(), encoded, nil, { xpcResponse in
            let result: Result<R, XPCError>
            if xpc_get_type(xpcResponse) == XPC_TYPE_DICTIONARY {
                do {
                    let response = try Response(dictionary: xpcResponse)
                    if response.containsPayload {
                        result = Result.success(try response.decodePayload(asType: R.self))
                    } else if response.containsError {
                        result = Result.failure(try response.decodeError())
                    } else {
                        result = Result.failure(.unknown)
                    }
                } catch let error as XPCError  {
                    result = Result.failure(error)
                } catch {
                    result = Result.failure(.unknown)
                }
            } else if xpc_equal(xpcResponse, XPC_ERROR_CONNECTION_INVALID) {
                result = Result.failure(.connectionInvalid)
            } else if xpc_equal(xpcResponse, XPC_ERROR_CONNECTION_INTERRUPTED) {
                result = Result.failure(.connectionInterrupted)
            } else if xpc_equal(xpcResponse, XPC_ERROR_TERMINATION_IMMINENT) {
                result = Result.failure(.terminationImminent)
            } else { // Unexpected
                result = Result.failure(.unknown)
            }
            reply(result)
        })
    }

	// MARK: Abstract methods
	
    /// Creates and returns connection for the mach service stored by this instance of the client.
    internal func createConnection() -> xpc_connection_t {
        fatalError("Abstract Method")
    }
}
