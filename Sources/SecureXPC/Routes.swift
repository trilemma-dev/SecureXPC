//
//  Routes.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-11-06
//

import Foundation

/// Consistent framework internal implementation of routes that can be sent over XPC (because its Codable) and used as a dictionary key (because its Hashable).
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

/// A route that can't receive a message and is expected to reply.
public struct XPCRouteWithoutMessageWithReply<R: Codable> {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - replyType: The expected type the server will respond with if successful.
    public init(_ pathComponents: String..., replyType: R.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: nil, replyType: replyType)
    }
}

/// A route that receives a message and is expected to reply.
public struct XPCRouteWithMessageWithReply<M: Codable, R: Codable> {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - messageType: The expected type the client will be passed when sending a message to this route.
    ///   - replyType: The expected type the server will respond with if successful.
    public init(_ pathComponents: String..., messageType: M.Type, replyType: R.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: messageType, replyType: replyType)
    }
}

/// A route that can't receive a message and will not reply.
public struct XPCRouteWithoutMessageWithoutReply {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    public init(_ pathComponents: String...) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: nil, replyType: nil)
    }
}

/// A route that receives a message and will not reply.
public struct XPCRouteWithMessageWithoutReply<M: Codable> {
    let route: XPCRoute
    
    /// Initializes the route.
    ///
    /// - Parameters:
    ///   - _: Zero or more `String`s naming the route.
    ///   - messageType: The expected type the client will be passed when sending a message to this route.
    public init(_ pathComponents: String..., messageType: M.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: messageType, replyType: nil)
    }
}
