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
/// In practice a route is similar to a function signature or a server path with type safety. Message and reply types must be
/// [`Codable`](https://developer.apple.com/documentation/swift/codable). Many structs, enums, and classes in the Swift standard library are
/// already `Codable` and compiler generated conformance is available for simple structs and enums.
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
/// Routes are distinct based on their names, meaning the last two routes above are considered equivalent. A server will only allow one handler to be registered for
/// each distinct route.
///
/// #### Errors
/// Errors thrown by the handler registered for the route may optionally be specified:
/// ```swift
/// let throttleRoute = XPCRoute.named("thermal", "throttle")
///                             .withMessageType(Int.self)
///                             .throwsType(ThermalError.self)
///                             .throwsType(ConfigurationError.self)                             
/// ```
/// Any number of error types which are `Codable` may be specified.
///
/// #### Storing Routes
/// To ensure consistency, ideally routes are only defined once in code that is shared by both the client and server.
///
/// #### Registering Routes
/// Once a route has been created, it needs to be registered with an ``XPCServer`` in order for it to be called by an ``XPCClient``.
///
/// #### Updating Routes
/// If you are using XPC Mach services, take care when updating existing routes because over time you may end up with an older version of your server installed on
/// a computer with a newer client. You may want to version your routes by prefixing them with a number:
/// ```swift
/// XPCRoute.named("1", "reset")
/// ```
///
/// This is also applicable for routes registered with anonymous servers that allow requests from other processes.
public struct XPCRoute {
    
    /// The key to be used when inserting or accessing an XPC route that's part of the coding process's user info
    static let codingUserInfoKey = CodingUserInfoKey(rawValue: String(describing: XPCRoute.self))!
    
    let pathComponents: [String]
    
    // These are intentionally excluded when computing equality and hash values as routes are uniqued only on path
    
    /// Whether the route expects the handler registered on the server to have a non-`Void` return type.
    ///
    /// The client may still request a response meaning that completion and any error that occurred can be sent back, but the server's handler is not expected to
    /// have a return type.
    let expectsReply: Bool
    /// Types that the API user claims could be thrown by the server's handler registered with this route.
    ///
    /// There's no way to compile time enforce this is actually true; however, at runtime the client will attempt to decode an error to these types.
    ///
    /// This array of types is intentionally not encoded/decoded as there is no way to transfer actual Swift types between runtimes and we need the actual types, not
    /// just textual descriptions of them. Since the server always attempts to encode any error it can, only the client actually needs these types.
    let errorTypes: [(Error & Codable).Type]
    
    let messageType: String?
    let replyType: String?
    let sequentialReplyType: String?
    
    /// Represents all valid route configurations.
    ///
    /// Using an enum to enumerate these cases is intended to prevent invalid configurations such as having both a reply and a sequential reply.
    enum RouteConfig {
        case withoutMessageWithoutReply
        case withoutMessageWithReply(Any.Type)
        case withoutMessageWithSequentialReply(Any.Type)
        case withMessageWithoutReply(Any.Type)
        case withMessageWithReply(Any.Type, Any.Type)
        case withMessageWithSequentialReply(Any.Type, Any.Type)
    }
    
    fileprivate init(pathComponents: [String],
                     routeConfig: RouteConfig,
                     errorTypes: [(Error & Codable).Type]) {
        self.pathComponents = pathComponents
        self.errorTypes = errorTypes
        
        switch routeConfig {
            case .withoutMessageWithoutReply:
                self.messageType = nil
                self.replyType = nil
                self.expectsReply = false
                self.sequentialReplyType = nil
            case .withoutMessageWithReply(let replyType):
                self.messageType = nil
                self.replyType = String(describing: replyType)
                self.expectsReply = replyType != Void.self
                self.sequentialReplyType = nil
            case .withoutMessageWithSequentialReply(let sequentialReplyType):
                self.messageType = nil
                self.replyType = nil
                self.expectsReply = false
                self.sequentialReplyType = String(describing: sequentialReplyType)
            case .withMessageWithoutReply(let messageType):
                self.messageType = String(describing: messageType)
                self.replyType = nil
                self.expectsReply = false
                self.sequentialReplyType = nil
            case .withMessageWithReply(let messageType, let replyType):
                self.messageType = String(describing: messageType)
                self.replyType = String(describing: replyType)
                self.expectsReply = replyType != Void.self
                self.sequentialReplyType = nil
            case .withMessageWithSequentialReply(let messageType, let sequentialReplyType):
                self.messageType = String(describing: messageType)
                self.replyType = nil
                self.expectsReply = false
                self.sequentialReplyType = String(describing: sequentialReplyType)
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
        XPCRouteWithoutMessageWithoutReply(pathComponents, errorTypes: [])
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

// Custom codable implementation that exists to prevent encoding `errorTypes`.
extension XPCRoute: Codable {
    private enum CodingKeys: String, CodingKey {
        case pathComponents
        case messageType
        case replyType
        case sequentialReplyType
        case expectsReply
        // It is intentional errorTypes is not coded, see errorTypes declaration for explanation.
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.pathComponents, forKey: .pathComponents)
        try container.encode(self.messageType, forKey: .messageType)
        try container.encode(self.replyType, forKey: .replyType)
        try container.encode(self.sequentialReplyType, forKey: .sequentialReplyType)
        try container.encode(self.expectsReply, forKey: .expectsReply)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pathComponents = try container.decode([String].self, forKey: .pathComponents)
        self.messageType = try container.decode(String?.self, forKey: .messageType)
        self.replyType = try container.decode(String?.self, forKey: .replyType)
        self.sequentialReplyType = try container.decode(String?.self, forKey: .sequentialReplyType)
        self.expectsReply = try container.decode(Bool.self, forKey: .expectsReply)
        self.errorTypes = []
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
    fileprivate init(_ pathComponents: [String], errorTypes: [(Error & Codable).Type]) {
        self.route = XPCRoute(pathComponents: pathComponents,
                              routeConfig: .withoutMessageWithoutReply,
                              errorTypes: errorTypes)
    }
    
    /// Optionally specifies an `Error` type thrown by the handler registered for this route.
    ///
    /// This function may be called multiple times to register multiple potential error types.
    ///
    /// For specified error types, if the client used an `async` function then the specific error will be rethrown. If a closure-based function was used, then it will be
    /// returned as an ``XPCError/handlerError(_:)`` and ``HandlerError/UnderlyingError-swift.enum/available(_:)`` will contain the
    /// specific error.
    ///
    /// If the error type thrown by the server was not specified using this function, then ``HandlerError`` will represent the error, and
    /// ``HandlerError/underlyingError-swift.property`` will have a value of
    /// ``HandlerError/UnderlyingError-swift.enum/unavailableNoDecodingPossible``. This will occur for both the `async` and
    /// closure-based functions.
    public func throwsType<E: Error & Codable>(_ errorType: E.Type) -> XPCRouteWithoutMessageWithoutReply {
        XPCRouteWithoutMessageWithoutReply(self.route.pathComponents,
                                           errorTypes: self.route.errorTypes + [errorType])
    }
    
    /// Creates a route which receives a message and will not reply.
    ///
    /// ``XPCRouteWithMessageWithoutReply/withReplyType(_:)`` can be called on it to create a route which is expected to reply.
    public func withMessageType<M: Codable>(_ messageType: M.Type) -> XPCRouteWithMessageWithoutReply<M> {
        XPCRouteWithMessageWithoutReply(self.route.pathComponents,
                                        messageType: M.self,
                                        errorTypes: self.route.errorTypes)
    }
    
    /// Creates a route that can't receive a message and is expected to reply.
    ///
    /// ``XPCRouteWithoutMessageWithReply/withMessageType(_:)`` can be called on the returned route to create a route that receives a message.
    public func withReplyType<R: Codable>(_ replyType: R.Type) -> XPCRouteWithoutMessageWithReply<R> {
        XPCRouteWithoutMessageWithReply(self.route.pathComponents,
                                        replyType: R.self,
                                        errorTypes: self.route.errorTypes)
    }
    
    /// Creates a route that can't receive a message and may reply with zero or more values.
    ///
    /// ``XPCRouteWithoutMessageWithSequentialReply/withMessageType(_:)`` can be called on the returned route to create a route that
    /// receives a message.
    public func withSequentialReplyType<S: Codable>(_ replyType: S.Type) -> XPCRouteWithoutMessageWithSequentialReply<S> {
        XPCRouteWithoutMessageWithSequentialReply(self.route.pathComponents,
                                                  sequentialReplyType: S.self,
                                                  errorTypes: self.route.errorTypes)
    }
}

/// A route that can't receive a message and is expected to reply.
///
/// See ``XPCRoute`` for how to create a route.
public struct XPCRouteWithoutMessageWithReply<R: Codable> {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - replyType: The expected type the server will respond with if successful.
    fileprivate init(_ pathComponents: [String], replyType: R.Type, errorTypes: [(Error & Codable).Type]) {
        self.route = XPCRoute(pathComponents: pathComponents,
                              routeConfig: .withoutMessageWithReply(R.self),
                              errorTypes: errorTypes)
    }
    
    /// Optionally specifies an `Error` type thrown by the handler registered for this route.
    ///
    /// This function may be called multiple times to register multiple potential error types.
    ///
    /// For specified error types, if the client used an `async` function then the specific error will be rethrown. If a closure-based function was used, then it will be
    /// returned as an ``XPCError/handlerError(_:)`` and ``HandlerError/UnderlyingError-swift.enum/available(_:)`` will contain the
    /// specific error.
    ///
    /// If the error type thrown by the server was not specified using this function, then ``HandlerError`` will represent the error, and
    /// ``HandlerError/underlyingError-swift.property`` will have a value of
    /// ``HandlerError/UnderlyingError-swift.enum/unavailableNoDecodingPossible``. This will occur for both the `async` and
    /// closure-based functions.
    public func throwsType<E: Error & Codable>(_ errorType: E.Type) -> XPCRouteWithoutMessageWithReply {
        XPCRouteWithoutMessageWithReply(self.route.pathComponents,
                                        replyType: R.self,
                                        errorTypes: self.route.errorTypes + [errorType])
    }
    
    /// Creates a route that receives a message and is expected to reply.
    public func withMessageType<M: Codable>(_ messageType: M.Type) -> XPCRouteWithMessageWithReply<M, R> {
        XPCRouteWithMessageWithReply(self.route.pathComponents,
                                     messageType: M.self,
                                     replyType: R.self,
                                     errorTypes: self.route.errorTypes)
    }
}

/// A route that receives a message and will not reply.
///
/// See ``XPCRoute`` for how to create a route.
public struct XPCRouteWithMessageWithoutReply<M: Codable> {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - messageType: The expected type the client will be passed when sending a message to this route.
    fileprivate init(_ pathComponents: [String], messageType: M.Type, errorTypes: [(Error & Codable).Type]) {
        self.route = XPCRoute(pathComponents: pathComponents,
                              routeConfig: .withMessageWithoutReply(M.self),
                              errorTypes: errorTypes)
    }
    
    /// Optionally specifies an `Error` type thrown by the handler registered for this route.
    ///
    /// This function may be called multiple times to register multiple potential error types.
    ///
    /// For specified error types, if the client used an `async` function then the specific error will be rethrown. If a closure-based function was used, then it will be
    /// returned as an ``XPCError/handlerError(_:)`` and ``HandlerError/UnderlyingError-swift.enum/available(_:)`` will contain the
    /// specific error.
    ///
    /// If the error type thrown by the server was not specified using this function, then ``HandlerError`` will represent the error, and
    /// ``HandlerError/underlyingError-swift.property`` will have a value of
    /// ``HandlerError/UnderlyingError-swift.enum/unavailableNoDecodingPossible``. This will occur for both the `async` and
    /// closure-based functions.
    public func throwsType<E: Error & Codable>(_ errorType: E.Type) -> XPCRouteWithMessageWithoutReply {
        XPCRouteWithMessageWithoutReply(self.route.pathComponents,
                                        messageType: M.self,
                                        errorTypes: self.route.errorTypes + [errorType])
    }
    
    /// Creates a route that receives a message and is expected to reply.
    public func withReplyType<R: Codable>(_ replyType: R.Type) -> XPCRouteWithMessageWithReply<M, R> {
        XPCRouteWithMessageWithReply(self.route.pathComponents,
                                     messageType: M.self,
                                     replyType: R.self,
                                     errorTypes: self.route.errorTypes)
    }
    
    /// Creates a route that receives a message and may reply with zero or more values.
    public func withSequentialReplyType<S: Codable>(
        _ sequentialReplyType: S.Type
    ) -> XPCRouteWithMessageWithSequentialReply<M, S> {
        XPCRouteWithMessageWithSequentialReply(self.route.pathComponents,
                                               messageType: M.self,
                                               sequentialReplyType: S.self,
                                               errorTypes: self.route.errorTypes)
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
    fileprivate init(_ pathComponents: [String],
                     messageType: M.Type,
                     replyType: R.Type,
                     errorTypes: [(Error & Codable).Type]) {
        self.route = XPCRoute(pathComponents: pathComponents,
                              routeConfig: .withMessageWithReply(M.self, R.self),
                              errorTypes: errorTypes)
    }
    
    /// Optionally specifies an `Error` type thrown by the handler registered for this route.
    ///
    /// This function may be called multiple times to register multiple potential error types.
    ///
    /// For specified error types, if the client used an `async` function then the specific error will be rethrown. If a closure-based function was used, then it will be
    /// returned as an ``XPCError/handlerError(_:)`` and ``HandlerError/UnderlyingError-swift.enum/available(_:)`` will contain the
    /// specific error.
    ///
    /// If the error type thrown by the server was not specified using this function, then ``HandlerError`` will represent the error, and
    /// ``HandlerError/underlyingError-swift.property`` will have a value of
    /// ``HandlerError/UnderlyingError-swift.enum/unavailableNoDecodingPossible``. This will occur for both the `async` and
    /// closure-based functions.
    public func throwsType<E: Error & Codable>(_ errorType: E.Type) -> XPCRouteWithMessageWithReply {
        XPCRouteWithMessageWithReply(self.route.pathComponents,
                                     messageType: M.self,
                                     replyType: R.self,
                                     errorTypes: self.route.errorTypes + [errorType])
    }
}

/// A route that can't receive a message and replies with one or more values.
///
/// See ``XPCRoute`` for how to create a route.

public struct XPCRouteWithoutMessageWithSequentialReply<S: Codable> {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - sequentialReplyType: The expected type the server will respond with if successful.
    fileprivate init(_ pathComponents: [String],
                     sequentialReplyType: S.Type,
                     errorTypes: [(Error & Codable).Type]) {
        self.route = XPCRoute(pathComponents: pathComponents,
                              routeConfig: .withoutMessageWithSequentialReply(S.self),
                              errorTypes: errorTypes)
    }
    
    /// Optionally specifies an `Error` type thrown by the handler registered for this route.
    ///
    /// This function may be called multiple times to register multiple potential error types.
    ///
    /// For specified error types, if the client used an `async` function then the specific error will be rethrown. If a closure-based function was used, then it will be
    /// returned as an ``XPCError/handlerError(_:)`` and ``HandlerError/UnderlyingError-swift.enum/available(_:)`` will contain the
    /// specific error.
    ///
    /// If the error type thrown by the server was not specified using this function, then ``HandlerError`` will represent the error, and
    /// ``HandlerError/underlyingError-swift.property`` will have a value of
    /// ``HandlerError/UnderlyingError-swift.enum/unavailableNoDecodingPossible``. This will occur for both the `async` and
    /// closure-based functions.
    public func throwsType<E: Error & Codable>(_ errorType: E.Type) -> XPCRouteWithoutMessageWithSequentialReply {
        XPCRouteWithoutMessageWithSequentialReply(self.route.pathComponents,
                                                  sequentialReplyType: S.self,
                                                  errorTypes: self.route.errorTypes + [errorType])
    }
    
    /// Creates a route that receives a message and may reply with zero or more values.
    public func withMessageType<M: Codable>(_ messageType: M.Type) -> XPCRouteWithMessageWithSequentialReply<M, S> {
        XPCRouteWithMessageWithSequentialReply(self.route.pathComponents,
                                               messageType: M.self,
                                               sequentialReplyType: S.self,
                                               errorTypes: self.route.errorTypes)
    }
}

/// A route that receives a message and replies with one or more values.
///
/// See ``XPCRoute`` for how to create a route.
public struct XPCRouteWithMessageWithSequentialReply<M: Codable, S: Codable> {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - messageType: The expected type the client will be passed when sending a message to this route.
    ///   - sequentialReplyType: The expected type the server will respond with if successful.
    fileprivate init(_ pathComponents: [String],
                     messageType: M.Type,
                     sequentialReplyType: S.Type,
                     errorTypes: [(Error & Codable).Type]) {
        self.route = XPCRoute(pathComponents: pathComponents,
                              routeConfig: .withMessageWithSequentialReply(M.self, S.self),
                              errorTypes: errorTypes)
    }
    
    /// Optionally specifies an `Error` type thrown by the handler registered for this route.
    ///
    /// This function may be called multiple times to register multiple potential error types.
    ///
    /// For specified error types, if the client used an `async` function then the specific error will be rethrown. If a closure-based function was used, then it will be
    /// returned as an ``XPCError/handlerError(_:)`` and ``HandlerError/UnderlyingError-swift.enum/available(_:)`` will contain the
    /// specific error.
    ///
    /// If the error type thrown by the server was not specified using this function, then ``HandlerError`` will represent the error, and
    /// ``HandlerError/underlyingError-swift.property`` will have a value of
    /// ``HandlerError/UnderlyingError-swift.enum/unavailableNoDecodingPossible``. This will occur for both the `async` and
    /// closure-based functions.
    public func throwsType<E: Error & Codable>(_ errorType: E.Type) -> XPCRouteWithMessageWithSequentialReply {
        XPCRouteWithMessageWithSequentialReply(self.route.pathComponents,
                                               messageType: M.self,
                                               sequentialReplyType: S.self,
                                               errorTypes: self.route.errorTypes + [errorType])
    }
}
