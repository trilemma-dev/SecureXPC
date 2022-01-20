//
//  XPCError.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-11-06
//

import Foundation

/// Errors that may be thrown when using ``XPCClient`` or ``XPCServer``.
public enum XPCError: Error, Codable {
    /// The connection was closed and can no longer be used; it may be possible to establish another connection.
    ///
    /// Corresponds to
    /// [`XPC_ERROR_CONNECTION_INVALID`](https://developer.apple.com/documentation/xpc/xpc_error_connection_invalid).
    case connectionInvalid
    /// The connection experienced an interruption, but is still valid.
    ///
    /// Corresponds to
    /// [`XPC_ERROR_CONNECTION_INTERRUPTED`](https://developer.apple.com/documentation/xpc/xpc_error_connection_interrupted).
    case connectionInterrupted
    /// This XPC service will be terminated imminently.
    ///
    /// Corresponds to
    /// [`XPC_ERROR_TERMINATION_IMMINENT`](https://developer.apple.com/documentation/xpc/xpc_error_termination_imminent).
    ///
    /// In practice this error is not expected to be encountered as this framework only supports XPC Mach service connections; this error applies to XPC Services
    /// which use a different type of connection.
    case terminationImminent
    /// The connection to the server has already experienced an interruption and cannot be reestablished under any circumstances.
    ///
    /// This is expected behavior when attempting to send a message to an anonymous server after the connection has been interrupted.
    case connectionCannotBeReestablished
    /// A request was not accepted by the server because it did not meet the server's security requirements or the server could not determine the identity of the
    /// client.
    case insecure
    /// Failed to encode a request or response in order to send it across the XPC connection.
    ///
    /// The associated value describes this encoding error.
    case encodingError(String)
    /// Failed to decode a request or response once it was received via the XPC connection.
    ///
    /// The associated value describes this decoding error.
    case decodingError(String)
    /// The route can't be registered because a route with this path already exists.
    case routeAlreadyRegistered([String])
    /// The route associated with the incoming XPC request is not registered with the ``XPCServer``.
    case routeNotRegistered([String])
    /// While the route associated with the incoming XPC request is registered with the ``XPCServer``, the message and/or reply does not match the handler
    /// registered with the server.
    ///
    /// The first associated value is the route's path components. The second is a descriptive error message.
    case routeMismatch([String], String)
    /// The caller is not a blessed helper tool or its property list configuration is not compatible with ``XPCServer/forThisBlessedHelperTool()``.
    case misconfiguredBlessedHelperTool(String)
    /// A server already exists for this named XPC Mach service and therefore another server can't be returned with different client requirements.
    case conflictingClientRequirements
    /// The caller is not an XPC Service.
    ///
    /// This may mean there is a configuration issue. Alternatively it could be the caller is an XPC Mach service, in which case use
    /// ``XPCServer/forThisMachService(named:clientRequirements:)`` instead.
    case notXPCService
    /// The caller is a misconfigured XPC Service.
    ///
    /// Currently, this means that its bundle idenifiter was not set.
    case misconfiguredXPCService
    /// An error occurred that is not part of this framework, for example an error thrown by a handler registered with a ``XPCServer`` route. The associated
    /// value describes the error.
    case other(String)
    /// Unknown error occurred.
    case unknown
    
    /// Represents the provided error as an ``XPCError``.
    ///
    /// - Parameters:
    ///   - error: The error to be represented as an ``XPCError``
    ///   - expectingNonXPCError: Whether an error which is not an ``XPCError``, `DecodingError`, or `EncodingError` is expected. If it is,
    ///   then its description will be returned as ``XPCError/other(_:)``, otherwise ``XPCError/unknown`` will be returned.
    /// - Returns: An ``XPCError`` to represent the passed in `error`
    internal static func asXPCError(error: Error, expectingOtherError: Bool) -> XPCError {
        if let error = error as? XPCError {
            return error
        } else if let error = error as? DecodingError {
            return .decodingError(String(describing: error))
        } else if let error = error as? EncodingError {
            return .encodingError(String(describing: error))
        } else if expectingOtherError {
            return .other(String(describing: error))
        } else {
            return .unknown
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
            return .unknown
        }
    }
}
