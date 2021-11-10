//
//  Request.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-11-05
//

import Foundation

/// A request sent across an XPC connection.
///
/// A request always contains a route and optionally contains a payload.
struct Request {
    
    private enum RequestKeys {
        static let route: XPCDictionaryKey = const("__route")
        static let payload: XPCDictionaryKey = const("__payload")
    }
    
    /// The route represented by this request.
    let route: XPCRoute
    /// Whether this request contains a payload.
    let containsPayload: Bool
    /// This request encoded as an XPC dictionary.
    ///
    /// If  `containsPayload` is `true` then `decodePayload` can be called to decode it; otherwise calling this function will result an error being thrown.
    let dictionary: xpc_object_t
    
    /// Represents a request that's already been encoded into an XPC dictionary.
    ///
    /// This initializer is expected to be used by the server when receiving a request which it now needs to decode.
    init(dictionary: xpc_object_t) throws {
        self.dictionary = dictionary
        self.route = try XPCDecoder.decode(XPCRoute.self, from: dictionary, forKey: RequestKeys.route)
        self.containsPayload = try XPCDecoder.containsKey(RequestKeys.payload, inDictionary: self.dictionary)
    }
    
    /// Represents a request without a payload which has yet to be encoded into an XPC dictionary.
    ///
    /// This initializer is expected to be used by the client in order to send a request across the XPC connection.
    init(route: XPCRoute) throws {
        self.route = route
        self.containsPayload = false
        
        self.dictionary = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(self.dictionary, RequestKeys.route, try XPCEncoder.encode(route))
    }
    
    /// Represents a request with a payload which has yet to be encoded into an XPC dictionary.
    ///
    /// This initializer is expected to be used by the client in order to send a request across the XPC connection.
    init<P: Encodable>(route: XPCRoute, payload: P) throws {
        self.route = route
        self.containsPayload = true
        
        self.dictionary = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(self.dictionary, RequestKeys.route, try XPCEncoder.encode(self.route))
        xpc_dictionary_set_value(dictionary, RequestKeys.payload, try XPCEncoder.encode(payload))
    }
    
    /// Decodes the payload as the provided type.
    ///
    /// This is expected to be called from the server.
    func decodePayload<T: Decodable>(asType type: T.Type) throws -> T {
        return try XPCDecoder.decode(type, from: self.dictionary, forKey: RequestKeys.payload)
    }
}
