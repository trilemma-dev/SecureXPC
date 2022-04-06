//
//  Response.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-11-05
//

import Foundation

/// A response which is sent to the client for requests which require one.
///
/// Due to how the XPC C API works, instances of this struct can only be created to represent an already received reply (which is expected to be done by the client).
/// The server must instead use the `encodePayload` and `encodeError` static functions.
struct Response {
    
    private enum ResponseKeys {
        static let error: XPCDictionaryKey = const("__error")
        static let payload: XPCDictionaryKey = const("__payload")
        static let requestID: XPCDictionaryKey = const("__request_id")
    }
    
    /// The route this response came from.
    let route: XPCRoute
    /// The unique identifier of the request which this response corresponds to.
    let requestID: UUID
    /// The response encoded as an XPC dictionary.
    let dictionary: xpc_object_t
    /// Whether this response contains a payload.
    let containsPayload: Bool
    /// Whether this response contains an error.
    let containsError: Bool
    
    /// Represents a reply that's already been encoded into an XPC dictionary.
    ///
    /// This initializer is expected to be used by the client when receiving a reply which it now needs to decode.
    init(dictionary: xpc_object_t, route: XPCRoute) throws {
        self.dictionary = dictionary
        self.route = route
        self.requestID = try XPCDecoder.decode(UUID.self, from: dictionary, forKey: ResponseKeys.requestID)
        self.containsPayload = try XPCDecoder.containsKey(ResponseKeys.payload, inDictionary: dictionary)
        self.containsError = try XPCDecoder.containsKey(ResponseKeys.error, inDictionary: dictionary)
    }
    
    /// Decodes the requestID inside of what is expected to be a response.
    ///
    /// This functionality is needed by the client when it receives an out-of-band response from the server and therefore doesn't know what route it corresponds
    /// to. By returning the requestID it's able to figure out what route it came from and then initialize a Response object.
    static func decodeRequestID(dictionary: xpc_object_t) throws -> UUID {
        try XPCDecoder.decode(UUID.self, from: dictionary, forKey: ResponseKeys.requestID)
    }
    
    /// Creates a partial response by directly encoding the payload into the provided XPC reply dictionary.
    ///
    /// This is expected to be used by the server. Due to how the XPC C API works the exact instance of reply dictionary provided by the API must be populated,
    /// it cannot be copied by value and therefore a `Response` instance can't be constructed.
    static func encodePayload<P: Encodable>(_ payload: P, intoReply reply: inout xpc_object_t) throws {
        xpc_dictionary_set_value(reply, ResponseKeys.payload, try XPCEncoder.encode(payload))
    }
    
    /// Creates a partial response by directly encoding the error into the provided XPC reply dictionary.
    ///
    /// This is expected to be used by the server. Due to how the XPC C API works the exact instance of reply dictionary provided by the API must be populated,
    /// it cannot be copied by value and therefore a `Response` instance can't be constructed.
    static func encodeError(_ error: XPCError, intoReply reply: inout xpc_object_t) throws {
        xpc_dictionary_set_value(reply, ResponseKeys.error, try XPCEncoder.encode(error))
    }
    
    /// Creates the remaining portion of a response by directly encoding the request ID into the XPC reply dictionary.
    static func encodeRequestID(_ requestID: UUID, intoReply reply: inout xpc_object_t) throws {
        xpc_dictionary_set_value(reply, ResponseKeys.requestID, try XPCEncoder.encode(requestID))
    }
    
    /// Decodes the reply as the provided type.
    ///
    /// This is expected to be called from the client.
    func decodePayload<T>(asType type: T.Type) throws -> T where T : Decodable {
        return try XPCDecoder.decode(type, from: self.dictionary, forKey: ResponseKeys.payload)
    }
    
    /// Decodes the reply as an ``XPCError``.
    ///
    /// This is expected to be called from the client.
    func decodeError() throws -> XPCError {
        return try XPCDecoder.decode(XPCError.self,
                                     from: self.dictionary,
                                     forKey: ResponseKeys.error,
                                     userInfo: [XPCRoute.codingUserInfoKey : self.route])
    }
}
