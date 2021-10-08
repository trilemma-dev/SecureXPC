//
//  XPCMachClient.swift
//  SwiftXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// Wrapper around the XPC C API to conveniently make XPC calls and receive responses
public struct XPCMachClient {
    
    // This client implementation intentionally does not store a reference to the xpc_connection_t as it can become
    // invalid for numerous reasons. Since it's expected relatively few messages will be sent and the lowest possible
    // latency isn't needed, it's simpler to always create the connection on demand each time a message is to be sent.
    
    private let machServiceName: String
    
    /// Creates a client which will attempt to send messages to the specified mach service
    public init(machServiceName: String) {
        self.machServiceName = machServiceName
    }
    
    /// Receives the result of a reply from an XPC message. The reply is either a message on success or an error on failure.
    public typealias MessageReply<R> = (Result<R, XPCError>) -> Void
    
    /// Sends with no message and will not receive a reply
    ///
    /// - Parameters:
    ///   - route: the server route which will handle this
    public func send(route: XPCRouteWithoutMessageWithoutReply) throws {
        let encoded = try XPCEncoder.encode(route: route.route)
        xpc_connection_send_message(createConnection(), encoded)
    }
    
    /// Sends a message which will not receive a response
    ///
    /// - Parameters:
    ///    - message: message to be sent
    ///    - route: the server route which should handle this message
    public func sendMessage<M: Encodable>(_ message: M, route: XPCRouteWithMessageWithoutReply<M>) throws {
        let encodedMessage = try XPCEncoder.encode(message, route: route.route)
        xpc_connection_send_message(createConnection(), encodedMessage)
    }
    
    /// Sends with no message and provides the reply as either a message on success or an error on failure.
    ///
    /// - Parameters:
    ///   - route: the server route which will handle this
    ///   - withReply: a function to receive the reply
    public func send<R: Decodable>(route: XPCRouteWithoutMessageWithReply<R>,
                                   withReply reply: @escaping MessageReply<R>) throws {
        let encoded = try XPCEncoder.encode(route: route.route)
        sendWithReply(encoded: encoded, withReply: reply)
    }
    
    /// Sends a message and provides the reply as either a message on success or an error on failure.
    ///
    /// - Parameters:
    ///    - message: message to be sent
    ///    - route: the server route which should handle this message
    ///    - withReply: a function to receive the message's reply
    public func sendMessage<M: Encodable, R: Decodable>(_ message: M,
                                                        route: XPCRouteWithMessageWithReply<M, R>,
                                                        withReply reply: @escaping MessageReply<R>) throws {
        let encodedMessage = try XPCEncoder.encode(message, route: route.route)
        sendWithReply(encoded: encodedMessage, withReply: reply)
    }
    
    private func sendWithReply<R: Decodable>(encoded: xpc_object_t,
                                             withReply reply: @escaping MessageReply<R>) {
        xpc_connection_send_message_with_reply(createConnection(), encoded, nil, { response in
            let result: Result<R, XPCError>
            if xpc_get_type(response) == XPC_TYPE_DICTIONARY {
                do {
                    if try XPCDecoder.containsPayload(response) {
                        let decodedResult = try XPCDecoder.decodePayload(response, asType: R.self)
                        result = Result.success(decodedResult)
                    } else if try XPCDecoder.containsError(response) {
                        let decodedError = try XPCDecoder.decodeError(response)
                        result = Result.failure(decodedError)
                    } else {
                        result = Result.failure(.unknown)
                    }
                } catch let error as XPCError  {
                    result = Result.failure(error)
                } catch {
                    result = Result.failure(.unknown)
                }
            } else if xpc_equal(response, XPC_ERROR_CONNECTION_INVALID) {
                result = Result.failure(.connectionInvalid)
            } else if xpc_equal(response, XPC_ERROR_CONNECTION_INTERRUPTED) {
                result = Result.failure(.connectionInterrupted)
            } else if xpc_equal(response, XPC_ERROR_TERMINATION_IMMINENT) {
                result = Result.failure(.terminationImminent)
            } else { // Unexpected
                result = Result.failure(.unknown)
            }
            reply(result)
        })
    }
    
    /// Creates and returns connection for the mach service stored by an instance of the client
    private func createConnection() -> xpc_connection_t {
        let connection = xpc_connection_create_mach_service(self.machServiceName, nil, 0)
        xpc_connection_set_event_handler(connection, { (event: xpc_object_t) in
            // A block *must* be set as the handler, even though this block does nothing.
            // If it were not set, a crash would occur upon calling xpc_connection_resume.
        })
        xpc_connection_resume(connection)
        
        return connection
    }
}
