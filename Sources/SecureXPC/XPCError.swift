//
//  XPCError.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-11-06
//

import Foundation

/// Errors that may be thrown when using ``XPCClient`` or ``XPCServer``.
public enum XPCError: Error, Codable {
    /// The connection is not valid, but could be valid in the future.
    ///
    /// The connection could be invalid because the service is not installed or the service was updated, severing an existing connection.
    case connectionInvalid
    /// The connection experienced an interruption, but is still valid.
    ///
    /// The next send may be able to successfully communicate with the server.
    case connectionInterrupted
    /// This XPC service will be terminated imminently.
    case terminationImminent
    /// A request failed due to not meeting security requirements.
    ///
    /// On the server this occurs when a request was not accepted due to not meeting the server's ``XPCServer/ClientRequirement`` or being unable to
    /// identify the client.
    ///
    /// On the client this occurs when a request was not made because the server does not meet the client's ``XPCClient/ServerRequirement``.
    case insecure
    /// A response cannot be sent because the client is no longer connected.
    case clientNotConnected
    /// A response cannot be sent because the sequence has already finished.
    case sequenceFinished
    /// Failed to encode a request or response in order to send it across the XPC connection.
    ///
    /// The associated value describes this encoding error.
    case encodingError(description: String)
    /// Failed to decode a request or response once it was received via the XPC connection.
    ///
    /// The associated value describes this decoding error.
    case decodingError(description: String)
    /// The route associated with the incoming request is not registered with the ``XPCServer``.
    case routeNotRegistered(routeName: [String])
    /// While the route associated with the incoming request is registered with the ``XPCServer``, the message and/or reply does not match the handler
    /// registered with the server.
    case routeMismatch(routeName:[String], description: String)
    /// A server already exists for this named XPC Mach service and therefore another server can't be returned with different client requirements.
    case conflictingClientRequirements
    /// This process's configuration prevents an ``XPCServer`` being retrieved for it or an ``XPCServer/ClientRequirement`` for being created for it.
    case misconfiguredServer(description: String)
    /// An error thrown by a handler registered with a ``XPCServer`` route when processing a client's request.
    ///
    /// The associated value represents, and possibly contains, the error.
    case handlerError(HandlerError)
    /// This process's configuration prevents an ``XPCClient/ServerRequirement`` for being created for it.
    case misconfiguredClient(description: String)
    /// An error internal to the SecureXPC framework.
    case internalFailure(description: String)
    /// Unknown error occurred.
    case unknown(description: String)
    
    /// Represents the provided error as an ``XPCError``.
    ///
    /// - Parameters:
    ///   - error: The error to be represented as an ``XPCError``
    /// - Returns: An ``XPCError`` to represent the passed in `error`
    internal static func asXPCError(error: Error) -> XPCError {
        if let error = error as? XPCError {
            return error
        } else if let error = error as? HandlerError {
            return .handlerError(error)
        } else if let error = error as? DecodingError {
            return .decodingError(description: String(describing: error))
        } else if let error = error as? EncodingError {
            return .encodingError(description: String(describing: error))
        } else {
            return .unknown(description: "Unexpected error received: \(error)")
        }
    }
    
    /// If the XPC object is an error it will be returned as the corresponding ``XPCError``, otherwise ``XPCError/unknown`` will be returned.
    internal static func fromXPCObject(_ object: xpc_object_t) -> XPCError {
        if xpc_equal(object, XPC_ERROR_CONNECTION_INVALID) {
            return .connectionInvalid
        } else if xpc_equal(object, XPC_ERROR_CONNECTION_INTERRUPTED) {
            return .connectionInterrupted
        } else if xpc_equal(object, XPC_ERROR_TERMINATION_IMMINENT) {
            return .terminationImminent
        } else {
            return .unknown(description: "Unexpected XPC object: \(object)")
        }
    }
}
