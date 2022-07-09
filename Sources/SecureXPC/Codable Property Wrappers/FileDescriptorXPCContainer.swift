//
//  FileDescriptorXPCContainer.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-10
//

import Foundation
import System

/// Wraps a [`FileDescriptor`](https://developer.apple.com/documentation/system/filedescriptor) such that it can be sent over an XPC
/// connection.
///
/// This property wrapper and ``FileHandleXPCContainer`` share an underlying representation and may be used interchangeably between the server
/// and client.
///
/// > Warning: While the resulting value conforms to `Codable` it can only be encoded and decoded by `SecureXPC`.
@available(macOS 11.0, *)
@propertyWrapper public struct FileDescriptorXPCContainer {
    public var wrappedValue: FileDescriptor
    private let closeOnEncode: Bool
    
    public init(wrappedValue: FileDescriptor, closeOnEncode: Bool = true) {
        self.wrappedValue = wrappedValue
        self.closeOnEncode = closeOnEncode
    }
}

@available(macOS 11.0, *)
extension FileDescriptorXPCContainer: Encodable {
    public func encode(to encoder: Encoder) throws {
        guard let xpcEncoder = encoder as? XPCEncoderImpl else {
            throw XPCCoderError.onlyEncodableBySecureXPCFramework
        }
        
        let container = xpcEncoder.xpcSingleValueContainer()
        guard let xpcEncodedForm = xpc_fd_create(wrappedValue.rawValue) else {
            let context = EncodingError.Context(codingPath: container.codingPath,
                                                debugDescription: "Encoding failed for \(wrappedValue)",
                                                underlyingError: nil)
            throw EncodingError.invalidValue(wrappedValue, context)
        }
        if closeOnEncode {
            try wrappedValue.close()
        }
        container.setAlreadyEncodedValue(xpcEncodedForm)
    }
}

@available(macOS 11.0, *)
extension FileDescriptorXPCContainer: Decodable {
    public init(from decoder: Decoder) throws {
        guard let xpcDecoder = decoder as? XPCDecoderImpl else {
            throw XPCCoderError.onlyDecodableBySecureXPCFramework
        }
        
        let container = xpcDecoder.xpcSingleValueContainer()
        let xpcEncodedForm = try container.accessAsEncodedValue(xpcType: XPC_TYPE_FD)
        let fd = xpc_fd_dup(xpcEncodedForm)
        // From xpc_fd_dup documentation: If the descriptor could not be created or if the given object was not an XPC
        // file descriptor, -1 is returned.
        if fd == -1 {
            let context = DecodingError.Context(codingPath: container.codingPath,
                                                debugDescription: "FileDescriptor could not be created",
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
        
        self.wrappedValue = FileDescriptor(rawValue: fd)
        self.closeOnEncode = true
    }
}
