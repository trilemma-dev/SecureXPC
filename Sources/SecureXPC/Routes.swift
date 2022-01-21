//
//  Routes.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-11-06
//

import Foundation

/// The entry point for creating routes needed for client to server communication.
///
/// Client to server communication is performed using routes. A route is a sequence of `String`s and if applicable also the message and reply types.
///
/// In practice a route is similar to a function signature or a server path with type safety, although it is not precisely either. Message and reply types must be
/// [`Codable`](https://developer.apple.com/documentation/swift/codable). Many structs, enums, and classes in the Swift
/// standard library are already `Codable` and compiler generated conformance is available for simple structs and enums.
///
/// The simplest form of a route is one that contains neither a message nor a reply:
/// ```swift
/// let resetRoute = XPCRoute.named("reset")
/// ```
///
/// In many cases a reply will be desired:
/// ```swift
/// let thermalLastSetRoute = XPCRoute.named("thermal", "lastSetAt")
///                                   .withReplyType(Date.self)
/// ```
///
/// Routes can have a message sent to them that don't have a reply:
/// ```swift
/// let setLimitRoute = XPCRoute.named("thermal", "setLimit")
///                             .withMessageType(Int.self)
/// ```
///
/// As well as those that do expect a reply:
/// ```swift
/// let setLimitRoute = XPCRoute.named("thermal", "setLimit")
///                             .withMessageType(Int.self)
///                             .withReplyType(Int.self)
/// ```
///
/// Routes are distinct based on their names, meaning the last two routes above are considered equivalent. A server will
/// only allow one handler to be registered for each distinct route.
///
/// #### Storing Routes
/// To ensure consistency, ideally routes are only defined once in code that is shared by both the client and server.
///
/// #### Registering Routes
/// Once a route has been created, it needs to be registered with an ``XPCServer`` in order for it to be called by an ``XPCClient``.
///
/// #### Updating Routes
/// If you are using XPC Mach services, take care when updating existing routes because over time you may end up with an
/// older version of your server installed on a computer with a newer client. You may want to version your routes by
/// prefixing them with a number:
/// ```swift
/// XPCRoute.named("1", "reset")
/// ```
///
/// This is also applicable for routes registered with anonymous servers that allow requests from other processes.
public struct XPCRoute: Codable {
    let pathComponents: [String]
    
    // These are intentionally excluded when computing equality and hash values as routes are uniqued only on path
    let messageType: String?
    let replyType: String?
    /// Whether the route expects the handler registered on the server to have a non-`Void` type.
    ///
    /// The client may still request a response meaning that completion and any error that occurred can be sent back, but the handler is not expected to return data.
    let expectsReply: Bool
    
    fileprivate init(pathComponents: [String], messageType: Any.Type?, replyType: Any.Type?) {
        self.pathComponents = pathComponents
        
        if let messageType = messageType {
            self.messageType = String(describing: messageType)
        } else {
            self.messageType = nil
        }
        
        if let replyType = replyType {
            self.replyType = String(describing: replyType)
            self.expectsReply = (replyType.self != Void.self)
        } else {
            self.replyType = nil
            self.expectsReply = false
        }
    }
    
    /// Creates a route that can't receive a message and will not reply.
    ///
    /// ``XPCRouteWithoutMessageWithoutReply/withMessageType(_:)`` can be called on the returned route to create a route that receives a
    /// message.
    ///
    /// ``XPCRouteWithoutMessageWithoutReply/withReplyType(_:)`` can be called on the returned route to create a route which is expected to
    /// reply.
    public static func named(_ pathComponents: String...) -> XPCRouteWithoutMessageWithoutReply {
        XPCRouteWithoutMessageWithoutReply(pathComponents)
    }
}

extension XPCRoute: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(pathComponents)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pathComponents == rhs.pathComponents
    }
}

/// A route that can't receive a message and will not reply.
///
/// See ``XPCRoute`` for how to create a route.
public struct XPCRouteWithoutMessageWithoutReply {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    fileprivate init(_ pathComponents: [String]) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: nil, replyType: nil)
    }
    
    /// Creates a route which receives a message and will not reply.
    ///
    /// ``XPCRouteWithMessageWithoutReply/withReplyType(_:)`` can be called on it to create a route which is expected to reply.
    public func withMessageType<M: Codable>(_ messageType: M.Type) -> XPCRouteWithMessageWithoutReply<M> {
        XPCRouteWithMessageWithoutReply(self.route.pathComponents, messageType: messageType)
    }
    
    /// Creates a route that can't receive a message and is expected to reply.
    ///
    /// ``XPCRouteWithoutMessageWithReply/withMessageType(_:)`` can be called on the returned route to create a route that receives a message.
    public func withReplyType<R: Codable>(_ replyType: R.Type) -> XPCRouteWithoutMessageWithReply<R> {
        XPCRouteWithoutMessageWithReply(self.route.pathComponents, replyType: replyType)
    }
}

/// A route that can't receive a message and is expected to reply.
///
/// See ``XPCRoute`` for how to create a route.
public struct XPCRouteWithoutMessageWithReply<R: Codable> {
    let route: XPCRoute
    private let replyType: R.Type
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - replyType: The expected type the server will respond with if successful.
    fileprivate init(_ pathComponents: [String], replyType: R.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: nil, replyType: replyType)
        self.replyType = replyType
    }
    
    /// Creates a route that receives a message and is expected to reply.
    public func withMessageType<M: Codable>(_ messageType: M.Type) -> XPCRouteWithMessageWithReply<M, R> {
        XPCRouteWithMessageWithReply(self.route.pathComponents, messageType: messageType, replyType: self.replyType)
    }
}

/// A route that receives a message and will not reply.
///
/// See ``XPCRoute`` for how to create a route.
public struct XPCRouteWithMessageWithoutReply<M: Codable> {
    private let messageType: M.Type
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - messageType: The expected type the client will be passed when sending a message to this route.
    fileprivate init(_ pathComponents: [String], messageType: M.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: messageType, replyType: nil)
        self.messageType = messageType
    }
    
    /// Creates a route that receives a message and is expected to reply.
    public func withReplyType<R: Codable>(_ replyType: R.Type) -> XPCRouteWithMessageWithReply<M, R> {
        XPCRouteWithMessageWithReply(self.route.pathComponents, messageType: self.messageType, replyType: replyType)
    }
}

/// A route that receives a message and is expected to reply.
///
/// See ``XPCRoute`` for how to create a route.
public struct XPCRouteWithMessageWithReply<M: Codable, R: Codable> {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - messageType: The expected type the client will be passed when sending a message to this route.
    ///   - replyType: The expected type the server will respond with if successful.
    fileprivate init(_ pathComponents: [String], messageType: M.Type, replyType: R.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: messageType, replyType: replyType)
    }
}
