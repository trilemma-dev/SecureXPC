//
//  XPCCommon.swift
//  SwiftXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// Errors that may be thrown when using ``XPCMachClient`` or ``XPCMachServer``
public enum XPCError: Error {
    /// The connection was closed and can no longer be used; it may be possible to establish another connection
    ///
    /// Corresponds to `XPC_ERROR_CONNECTION_INVALID`
    case connectionInvalid
    /// The connection experienced an interruption, but is still valid
    ///
    /// Corresponds to `XPC_ERROR_CONNECTION_INTERRUPTED`
    case connectionInterrupted
    /// This XPC service will be terminated imminently; be prepated to exit cleanly
    ///
    /// Corresponds to `XPC_ERROR_TERMINATION_IMMINENT`
    case terminationImminent
    /// A message was not accepted by the server because it did not meet the server's security requirements or the server could not determine the identity of the
    /// client
    case insecure
    /// An error occurred on the server, the associated value textually describes what went wrong
    ///
    /// The underlying error intentionally is an associated value as it may not exist within the client process
    case remote(String)
    /// Failed to encode an XPC type in order to send it across the XPC connection
    ///
    /// The associated value describes this encoding error
    case encodingError(EncodingError)
    /// Failed to decode an XPC type once it was received via the XPC connection
    ///
    /// The associated value describes this decoding error
    case decodingError(DecodingError)
    /// The route associated with the incoming XPC message is not registed with the server
    case routeNotRegistered(String)
    /// An underlying error occurred which was not anticipated, the associated value is this error
    case other(Error)
    /// Unknown error occurred
    case unknown
}

enum XPCCoderConstants {
    static let payload = "__payload"
    static let route = "__route"
    static let error = "__error"
}

struct XPCRoute: Codable, Hashable {
    let pathComponents: [String]
    let messageType: String?
    let replyType: String?
    
    init(pathComponents: [String], messageType: Any.Type?, replyType: Any.Type?) {
        self.pathComponents = pathComponents
        
        if let messageType = messageType {
            self.messageType = String(describing: messageType)
        } else {
            self.messageType = nil
        }
        
        if let replyType = replyType {
            self.replyType = String(describing: replyType)
        } else {
            self.replyType = nil
        }
    }
}

/// A route that can't receive a message and is expected to reply
public struct XPCRouteWithoutMessageWithReply<R: Codable> {
    let route: XPCRoute
    
    /// Initializes the immutable route
    ///
    /// - Parameters:
    ///   - _: zero or more `String`s naming the route
    ///   - replyType: the expected type the server will respond with if successful
    public init(_ pathComponents: String..., replyType: R.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: nil, replyType: replyType)
    }
}

/// A route that receives a message and is expected to reply
public struct XPCRouteWithMessageWithReply<M: Codable, R: Codable> {
    let route: XPCRoute
    
    /// Initializes the immutable route
    ///
    /// - Parameters:
    ///   - _: zero or more `String`s naming the route
    ///   - messageType: the expected type the client will be passed when sending a message to this route
    ///   - replyType: the expected type the server will respond with if successful
    public init(_ pathComponents: String..., messageType: M.Type, replyType: R.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: messageType, replyType: replyType)
    }
}

/// A route that can't receive a message and will not reply
public struct XPCRouteWithoutMessageWithoutReply {
    let route: XPCRoute
    
    /// Initializes the immutable route
    ///
    /// - Parameters:
    ///   - _: zero or more `String`s naming the route
    public init(_ pathComponents: String...) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: nil, replyType: nil)
    }
}

/// A route that receives a message and will not reply
public struct XPCRouteWithMessageWithoutReply<M: Codable> {
    let route: XPCRoute
    
    /// Initializes the immutable route
    ///
    /// - Parameters:
    ///   - _: zero or more `String`s naming the route
    ///   - messageType: the expected type the client will be passed when sending a message to this route
    public init(_ pathComponents: String..., messageType: M.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: messageType, replyType: nil)
    }
}
