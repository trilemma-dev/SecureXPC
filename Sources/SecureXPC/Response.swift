//
//  Response.swift
//  
//
//  Created by Josh Kaplan on 2021-11-05
//

import Foundation

/// A response which is sent to the client for requests which require one.
///
/// Due to how the XPC C API works, instances of this struct can only be created to represent an already received reply (which is expected to be done by the client).
/// The server must instead use the `encodePayload` and `encodedError` static functions.
struct Response {
    
    private enum ResponseKeys {
        static let error: XPCDictionaryKey = strdup("__error")!
        static let payload: XPCDictionaryKey = strdup("__payload")!
    }
    
    /// The response encoded as an XPC dictionary.
    let dictionary: xpc_object_t
    /// Whether this response contains a payload.
    let containsPayload: Bool
    /// Whether this response contains an error.
    let containsError: Bool
    
    /// Represents a reply that's already been encoded into an XPC dictionary.
    ///
    /// This initializer is expected to be used by the client when receiving a reply which it now needs to decode.
    init(dictionary: xpc_object_t) throws {
        self.dictionary = dictionary
        self.containsPayload = try XPCDecoder.containsKey(ResponseKeys.payload, inDictionary: dictionary)
        self.containsError = try XPCDecoder.containsKey(ResponseKeys.error, inDictionary: dictionary)
    }
    
    /// Create a response by directly encloding the payload into the provided XPC reply dictionary.
    ///
    /// This is expected to be used by the server. Due to how the XPC C API works the exact instance of reply dictionary provided by the API must be populated,
    /// it cannot be copied by value and therefore a `Reponse` instance can't be constructed.
    static func encodePayload<P: Encodable>(_ payload: P, intoReply reply: inout xpc_object_t) throws {
        xpc_dictionary_set_value(reply, ResponseKeys.payload, try XPCEncoder.encode(payload))
    }
    
    /// Create a response by directly encloding the error into the provided XPC reply dictionary.
    ///
    /// This is expected to be used by the server. Due to how the XPC C API works the exact instance of reply dictionary provided by the API must be populated,
    /// it cannot be copied by value and therefore a `Reponse` instance can't be constructed.
    static func encodeError(_ error: Error, intoReply reply: inout xpc_object_t) throws {
        let encodedError = try XPCEncoder.encode(String(describing: error))
        xpc_dictionary_set_value(reply, ResponseKeys.payload, encodedError)
    }
    
    /// Decodes the reply as the provided type.
    ///
    /// This is expected to be called from the client.
    func decodePayload<T>(asType type: T.Type) throws -> T where T : Decodable {
        return try XPCDecoder.decode(type, from: self.dictionary, forKey: ResponseKeys.payload)
    }
    
    /// Decodes the reply as an ``XPCError/remote(_:)`` instance which textually describes the error which occurred in the server.
    ///
    /// This is expected to be called from the client.
    func decodeError() throws -> XPCError {
        let errorMessage = try XPCDecoder.decode(String.self, from: self.dictionary, forKey: ResponseKeys.error)
            
        return XPCError.remote(errorMessage)
    }
}
