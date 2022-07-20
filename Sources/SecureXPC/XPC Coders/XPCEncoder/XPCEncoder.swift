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
        if let encodedValue = directEncode(value) {
            return encodedValue
        }
        
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
    
    /// For `Data` and arrays of certain fixed size value types, completely bypasses their `Encodable` implementation. If not applicable, `nil` is returned.
    private static func directEncode<T: Encodable>(_ value: T) -> xpc_object_t? {
        if let data = value as? Data {
            return data.withUnsafeBytes { xpc_data_create($0.baseAddress, data.count) }
        }
        
        // Try direct encoding as an array
        return encodeArrayAsData(value: value)
    }
}
