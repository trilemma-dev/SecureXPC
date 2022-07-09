//
//  FileHandleXPCContainer.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-09
//

import Foundation

/// Wraps a [`FileHandle`](https://developer.apple.com/documentation/foundation/filehandle) such that it can be sent over an XPC
/// connection.
///
/// This property wrapper and ``FileDescriptorXPCContainer`` share an underlying representation and may be used interchangeably between the server
/// and client.
///
/// > Warning: While the resulting value conforms to `Codable` it can only be encoded and decoded by `SecureXPC`.
@propertyWrapper public struct FileHandleXPCContainer {
    public var wrappedValue: FileHandle
    private let closeOnEncode: Bool
    
    public init(wrappedValue: FileHandle, closeOnEncode: Bool = true) {
        self.wrappedValue = wrappedValue
        self.closeOnEncode = closeOnEncode
    }
}

extension FileHandleXPCContainer: Encodable {
    public func encode(to encoder: Encoder) throws {
        guard let xpcEncoder = encoder as? XPCEncoderImpl else {
            throw XPCCoderError.onlyEncodableBySecureXPCFramework
        }
        
        let container = xpcEncoder.xpcSingleValueContainer()
        guard let xpcEncodedForm = xpc_fd_create(wrappedValue.fileDescriptor) else {
            let context = EncodingError.Context(codingPath: container.codingPath,
                                                debugDescription: "Encoding failed for \(wrappedValue)",
                                                underlyingError: nil)
            throw EncodingError.invalidValue(wrappedValue, context)
        }
        if closeOnEncode {
            if #available(macOS 10.15, *) {
                try wrappedValue.close()
            } else {
                wrappedValue.closeFile()
            }
        }
        container.setAlreadyEncodedValue(xpcEncodedForm)
    }
}

extension FileHandleXPCContainer: Decodable {
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
                                                debugDescription: "File handle could not be created",
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
        
        self.wrappedValue = FileHandle(fileDescriptor: fd)
        self.closeOnEncode = true
    }
}
