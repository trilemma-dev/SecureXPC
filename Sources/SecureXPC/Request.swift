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
        static let requestID: XPCDictionaryKey = const("__request_id")
        static let clientBookmark: XPCDictionaryKey = const("__client_bookmark")
    }
    
    /// The route represented by this request.
    let route: XPCRoute
    /// The unique identifier for this request.
    let requestID: UUID
    /// Whether this request contains a payload.
    let containsPayload: Bool
    /// This request encoded as an XPC dictionary.
    ///
    /// If  `containsPayload` is `true` then `decodePayload` can be called to decode it; otherwise calling this function will result an error being thrown.
    let dictionary: xpc_object_t
    /// A bookmark of the client's bundle. This allows a sandboxed server to validate the client's identity.
    let clientBookmark: Data
    
    /// Represents a request that's already been encoded into an XPC dictionary.
    ///
    /// This initializer is expected to be used by the server when receiving a request which it now needs to decode.
    init(dictionary: xpc_object_t) throws {
        self.dictionary = dictionary
        self.route = try XPCDecoder.decode(XPCRoute.self, from: dictionary, forKey: RequestKeys.route)
        self.requestID = try XPCDecoder.decode(UUID.self, from: dictionary, forKey: RequestKeys.requestID)
        self.clientBookmark = try XPCDecoder.decode(Data.self, from: dictionary, forKey: RequestKeys.clientBookmark)
        self.containsPayload = try XPCDecoder.containsKey(RequestKeys.payload, inDictionary: self.dictionary)
    }
    
    /// Decodes just the client bookmark for a request that's already been encoded into an XPC dictionary.
    ///
    /// This is expected to be used by the server when determining whether to accept a request. Because the request could be an attempted exploit, this function
    /// exists to minimize the amount of decoding we're doing (in comparison to initializing a Request instance) to reduce the exploitable surface area.
    static func decodeClientBookmark(dictionary: xpc_object_t) throws -> Data {
        return try XPCDecoder.decode(Data.self, from: dictionary, forKey: RequestKeys.clientBookmark)
    }
    
    /// Represents a request without a payload which has yet to be encoded into an XPC dictionary.
    ///
    /// This initializer is expected to be used by the client in order to send a request across the XPC connection.
    init(route: XPCRoute) throws {
        self.route = route
        self.requestID = UUID()
        self.containsPayload = false
        self.clientBookmark = try Bundle.main.bundleURL.bookmarkData()
        
        self.dictionary = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(self.dictionary, RequestKeys.route, try XPCEncoder.encode(route))
        xpc_dictionary_set_value(self.dictionary, RequestKeys.requestID, try XPCEncoder.encode(requestID))
        xpc_dictionary_set_value(self.dictionary, RequestKeys.clientBookmark, try XPCEncoder.encode(clientBookmark))
    }
    
    /// Represents a request with a payload which has yet to be encoded into an XPC dictionary.
    ///
    /// This initializer is expected to be used by the client in order to send a request across the XPC connection.
    init<P: Encodable>(route: XPCRoute, payload: P) throws {
        self.route = route
        self.requestID = UUID()
        self.containsPayload = true
        self.clientBookmark = try Bundle.main.bundleURL.bookmarkData()
        
        self.dictionary = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(self.dictionary, RequestKeys.route, try XPCEncoder.encode(self.route))
        xpc_dictionary_set_value(self.dictionary, RequestKeys.requestID, try XPCEncoder.encode(requestID))
        xpc_dictionary_set_value(self.dictionary, RequestKeys.payload, try XPCEncoder.encode(payload))
        xpc_dictionary_set_value(self.dictionary, RequestKeys.clientBookmark, try XPCEncoder.encode(clientBookmark))
    }
    
    /// Decodes the payload as the provided type.
    ///
    /// This is expected to be called from the server.
    func decodePayload<T: Decodable>(asType type: T.Type) throws -> T {
        return try XPCDecoder.decode(type, from: self.dictionary, forKey: RequestKeys.payload)
    }
}
