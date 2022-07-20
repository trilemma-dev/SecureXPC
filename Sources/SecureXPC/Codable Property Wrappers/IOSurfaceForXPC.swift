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
/// When creating an ``XPCRoute`` that directly transfers this type as either the message or reply type, `IOSurfaceForXPC` must be the specified type, not
/// `IOSurface`. This is not applicable when transferring a type which _contains_ a wrapped `IOSurface` as one of its properties.
@available(macOS 10.12, *)
@propertyWrapper public struct IOSurfaceForXPC {
    public var wrappedValue: IOSurface
    
    public init(wrappedValue: IOSurface) {
        self.wrappedValue = wrappedValue
    }
}

// MARK: Codable

@available(macOS 10.12, *)
extension IOSurfaceForXPC: Encodable {
    public func encode(to encoder: Encoder) throws {
        let xpcEncoder = try XPCEncoderImpl.asXPCEncoderImpl(encoder)
        xpcEncoder.xpcSingleValueContainer().setAlreadyEncodedValue(IOSurfaceCreateXPCObject(self.wrappedValue))
    }
}

@available(macOS 10.12, *)
extension IOSurfaceForXPC: Decodable {
    public init(from decoder: Decoder) throws {
        let xpcDecoder = try XPCDecoderImpl.asXPCDecoderImpl(decoder)
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
