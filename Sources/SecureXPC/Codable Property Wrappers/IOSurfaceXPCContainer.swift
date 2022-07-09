//
//  IOSurfaceXPCContainer.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-09
//

import Foundation
import IOSurface

/// Wraps an [`IOSurface`](https://developer.apple.com/documentation/iosurface) such that it can be sent over an XPC connection.
///
/// > Warning: While the resulting value conforms to `Codable` it can only be encoded and decoded by `SecureXPC`.
@available(macOS 10.12, *)
@propertyWrapper public struct IOSurfaceXPCContainer {
    public var wrappedValue: IOSurface
    
    public init(wrappedValue: IOSurface) {
        self.wrappedValue = wrappedValue
    }
}

// MARK: Codable

@available(macOS 10.12, *)
extension IOSurfaceXPCContainer: Encodable {
    public func encode(to encoder: Encoder) throws {
        guard let xpcEncoder = encoder as? XPCEncoderImpl else {
            throw XPCCoderError.onlyEncodableBySecureXPCFramework
        }
        
        xpcEncoder.xpcSingleValueContainer().setAlreadyEncodedValue(IOSurfaceCreateXPCObject(self.wrappedValue))
    }
}

@available(macOS 10.12, *)
extension IOSurfaceXPCContainer: Decodable {
    public init(from decoder: Decoder) throws {
        guard let xpcDecoder = decoder as? XPCDecoderImpl else {
            throw XPCCoderError.onlyDecodableBySecureXPCFramework
        }
        
        let container = xpcDecoder.xpcSingleValueContainer()
        guard let ioSurface = IOSurfaceLookupFromXPCObject(container.value) else {
            let debugDescription = "IOSurfaceRef could not be looked up from \(container.value)"
            let context = DecodingError.Context(codingPath: container.codingPath,
                                                debugDescription: debugDescription,
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
        
        self.wrappedValue = ioSurface
    }
}
