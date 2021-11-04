//
//  Request.swift
//  
//
//  Created by Josh Kaplan on 2021-11-05
//

import Foundation

private enum RequestKeys {
    static let route = "__route"
    static let payload = "__payload"
}

/// A request sent by the client not containing a payload.
struct SendableRequest {
    let route: XPCRoute
    
    func encode() throws -> xpc_object_t {
        let dictionary = xpc_dictionary_create(nil, nil, 0)
        let encodedRoute = try XPCEncoder.encode(self.route)
        RequestKeys.route.utf8CString.withUnsafeBufferPointer { keyPointer in
            xpc_dictionary_set_value(dictionary, keyPointer.baseAddress!, encodedRoute)
        }
        
        return dictionary
    }
}

/// A request sent by the client containing a payload.
struct SendableRequestWithPayload<P: Encodable> {
    let route: XPCRoute
    let payload: P
    
    func encode() throws -> xpc_object_t {
        let dictionary = xpc_dictionary_create(nil, nil, 0)
        let encodedRoute = try XPCEncoder.encode(self.route)
        RequestKeys.route.utf8CString.withUnsafeBufferPointer { keyPointer in
            xpc_dictionary_set_value(dictionary, keyPointer.baseAddress!, encodedRoute)
        }
        let encodedPayload = try XPCEncoder.encode(payload)
        RequestKeys.payload.utf8CString.withUnsafeBufferPointer { keyPointer in
            xpc_dictionary_set_value(dictionary, keyPointer.baseAddress!, encodedPayload)
        }
        
        return dictionary
    }
}

/// A representation of a request received by the server.
struct ReceivedRequest {
    let route: XPCRoute
    private let dictionary: xpc_object_t
    
    init(dictionary: xpc_object_t) throws {
        self.dictionary = dictionary
        self.route = try XPCDecoder.decode(XPCRoute.self, from: dictionary, forKey: RequestKeys.route)
    }
    
    func containsPayload() throws -> Bool {
        return try XPCDecoder.containsKey(RequestKeys.payload, inDictionary: self.dictionary)
    }
    
    func decodePayload<T>(asType type: T.Type) throws -> T where T : Decodable {
        return try XPCDecoder.decode(type, from: self.dictionary, forKey: RequestKeys.payload)
    }
}
