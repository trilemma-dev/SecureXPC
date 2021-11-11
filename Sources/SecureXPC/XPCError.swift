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
    /// The route associated with the incoming XPC request is not registed with the server.
    case routeNotRegistered(String)
    /// The calling program's property list configuration is not compatible with ``XPCServer/forThisBlessedHelperTool()``.
    case misconfiguredBlessedHelperTool(String)
    /// An error occurred that is not part of this framework, for example an error thrown by a handler registered with a ``XPCServer`` route. The associated
    /// value describes the error.
    case other(String)
    /// Unknown error occurred.
    case unknown
}
