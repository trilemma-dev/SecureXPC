//
//  XPCEncoder.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// Package internal entry point to encoding values as XPC objects.
enum XPCEncoder {
    
    /// Encodes the value as an XPC object.
    ///
    /// - Parameters:
    ///  - _: The value to be encoded.
    /// - Throws: If unable to encode the value.
    /// - Returns: Value as an XPC object.
    static func encode<T: Encodable>(_ value: T) throws -> xpc_object_t {
        let encoder = XPCEncoderImpl(codingPath: [CodingKey]())
        try value.encode(to: encoder)
        guard let encodedValue = try encoder.encodedValue() else {
            let context = EncodingError.Context(codingPath: [CodingKey](),
                                                debugDescription: "value failed to encode itself",
                                                underlyingError: nil)
            throw EncodingError.invalidValue(value, context)
        }
        
        return encodedValue
    }
}
