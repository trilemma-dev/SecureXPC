//
//  XPCCommon.swift
//  SwiftXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

public enum XPCError: Error {
    /// `XPC_ERROR_CONNECTION_INVALID` - connection closed by peer
    case connectionInvalid
    /// `XPC_ERROR_CONNECTION_INTERRUPTED` - re-sync state to other end if needed
    case connectionInterrupted
    /// `XPC_ERROR_TERMINATION_IMMINENT` - prepare to exit cleanly
    case terminationImminent
    /// Message not accepted because it did not meet the server's security requirements
    case insecure
    /// An error occurred on the server, the associated value textually describes what went wrong to aid in debugging
    case remote(String)
    /// If an `xpc_object_t` instance was encountered that is not an XPC dictionary, but was required to be
    case notXPCDictionary
    /// Failed to encode an XPC type
    case encodingError(EncodingError)
    /// Failed to decode an XPC type
    case decodingError(DecodingError)
    /// Route associated with the incoming XPC message is not registed with the server
    case routeNotRegistered(String)
    /// An underlying error occurred which was not anticipated
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
    let responseType: String?
    
    init(pathComponents: [String], messageType: Any.Type?, responseType: Any.Type?) {
        self.pathComponents = pathComponents
        
        if let messageType = messageType {
            self.messageType = String(describing: messageType)
        } else {
            self.messageType = nil
        }
        
        if let responseType = responseType {
            self.responseType = String(describing: responseType)
        } else {
            self.responseType = nil
        }
    }
}

public struct XPCRouteWithoutMessageWithReply<R: Codable> {
    let route: XPCRoute
    
    public init(_ pathComponents: String..., responseType: R.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: nil, responseType: responseType)
    }
}

public struct XPCRouteWithMessageWithReply<M: Codable, R: Codable> {
    let route: XPCRoute
    
    public init(_ pathComponents: String..., messageType: M.Type, responseType: R.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: messageType, responseType: responseType)
    }
}

public struct XPCRouteWithoutMessageWithoutReply {
    let route: XPCRoute
    
    public init(_ pathComponents: String...) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: nil, responseType: nil)
    }
}

public struct XPCRouteWithMessageWithoutReply<M: Codable> {
    let route: XPCRoute
    
    public init(_ pathComponents: String..., messageType: M.Type) {
        self.route = XPCRoute(pathComponents: pathComponents, messageType: messageType, responseType: nil)
    }
}
