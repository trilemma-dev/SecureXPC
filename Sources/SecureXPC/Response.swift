//
//  Response.swift
//  
//
//  Created by Josh Kaplan on 2021-11-05
//

import Foundation
import CryptoKit

private enum ResponseKeys {
    static let error = "__error"
    static let payload = "__payload"
}

/// A reply sendable by the server.
struct SendableResponseWithPayload<P: Encodable> {
    private let payload: P
    
    init(_ payload: P) {
        self.payload = payload
    }
    
    func encode(_ reply: inout xpc_object_t) throws {
        let encodedPayload = try XPCEncoder.encode(self.payload)
        ResponseKeys.payload.utf8CString.withUnsafeBufferPointer { keyPointer in
            xpc_dictionary_set_value(reply, keyPointer.baseAddress!, encodedPayload)
        }
    }
}

/// An error sendable by the server.
struct SendableResponseWithError {
    private let error: Error
    
    init(_ error: Error) {
        self.error = error
    }
    
    func encode(_ reply: inout xpc_object_t) throws {
        let encodedError = try XPCEncoder.encode(String(describing: error))
        ResponseKeys.payload.utf8CString.withUnsafeBufferPointer { keyPointer in
            xpc_dictionary_set_value(reply, keyPointer.baseAddress!, encodedError)
        }
    }
}

/// A response containing either an error or a reply received by the client.
struct ReceivedResponse {
    private let dictionary: xpc_object_t
    
    init(dictionary: xpc_object_t) {
        self.dictionary = dictionary
    }
    
    func containsPayload() throws -> Bool {
        return try XPCDecoder.containsKey(ResponseKeys.payload, inDictionary: self.dictionary)
    }
    
    func decodePayload<T>(asType type: T.Type) throws -> T where T : Decodable {
        return try XPCDecoder.decode(type, from: self.dictionary, forKey: ResponseKeys.payload)
    }
    
    func containsError() throws -> Bool {
        return try XPCDecoder.containsKey(ResponseKeys.error, inDictionary: self.dictionary)
    }
    
    func decodeError() throws -> XPCError {
        let errorMessage = try XPCDecoder.decode(String.self, from: self.dictionary, forKey: ResponseKeys.error)
            
        return XPCError.remote(errorMessage)
    }
}
