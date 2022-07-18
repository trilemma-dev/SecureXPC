//
//  DataOptimizedForXPC.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-19
//

import Foundation


/// Wraps a [`Data`](https://developer.apple.com/documentation/foundation/data) instance to optimize how it is sent over an XPC connection.
///
/// Usage of this property wrapper is never required and has no benefit when `Data` is either the message or reply type for an ``XPCRoute``.  When transferring
/// a type which _contains_ a `Data` property it is more efficient both in runtime and memory usage to wrap it using this property wrapper.
@propertyWrapper public struct DataOptimizedForXPC {
    public var wrappedValue: Data
    
    public init(wrappedValue: Data) {
        self.wrappedValue = wrappedValue
    }
}

// MARK: Codable

extension DataOptimizedForXPC: Encodable {
    public func encode(to encoder: Encoder) throws {
        let xpcEncoder = try XPCEncoderImpl.asXPCEncoderImpl(encoder)
        let encodedValue = wrappedValue.withUnsafeBytes { xpc_data_create($0.baseAddress, self.wrappedValue.count) }
        xpcEncoder.xpcSingleValueContainer().setAlreadyEncodedValue(encodedValue)
    }
}

extension DataOptimizedForXPC: Decodable {
    public init(from decoder: Decoder) throws {
        let xpcDecoder = try XPCDecoderImpl.asXPCDecoderImpl(decoder)
        let container = xpcDecoder.xpcSingleValueContainer()
        let value = container.value
        
        guard xpc_get_type(value) == XPC_TYPE_DATA, let pointer = xpc_data_get_bytes_ptr(value) else {
            let debugDescription = "Unable to decode \(container.value.description) to \(Data.self) instance"
            let context = DecodingError.Context(codingPath: container.codingPath,
                                                debugDescription: debugDescription,
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
        
        self.wrappedValue = Data(bytes: pointer, count: xpc_data_get_length(value))
    }
}
