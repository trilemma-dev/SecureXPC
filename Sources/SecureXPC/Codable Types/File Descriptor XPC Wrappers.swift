//
//  File Descriptor XPC Wrappers.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-10
//

import Foundation
import System

// MARK: common implementation

private protocol FileDescriptorCodable: Codable {
    init(descriptor: CInt, closeOnEncode: Bool)
    var descriptor: CInt { get }
    var closeOnEncode: Bool { get }
    func close() throws
}

private enum CodingKeys: String, CodingKey {
    case descriptor
    case closeOnEncode
}

extension FileDescriptorCodable {
    public func encode(to encoder: Encoder) throws {
        let container = try XPCEncoderImpl.asXPCEncoderImpl(encoder).xpcContainer(keyedBy: CodingKeys.self)
        guard let encodedDescriptor = xpc_fd_create(self.descriptor) else {
            let context = EncodingError.Context(codingPath: container.codingPath,
                                                debugDescription: "Encoding failed for \(self.descriptor)",
                                                underlyingError: nil)
            throw EncodingError.invalidValue(self.descriptor, context)
        }
        
        if self.closeOnEncode {
            try self.close()
        }
        container.encode(encodedDescriptor, forKey: CodingKeys.descriptor)
        try container.encode(self.closeOnEncode, forKey: CodingKeys.closeOnEncode)
    }
}

extension FileDescriptorCodable {
    public init(from decoder: Decoder) throws {
        let container = try XPCDecoderImpl.asXPCDecoderImpl(decoder).xpcContainer(keyedBy: CodingKeys.self)
        let descriptor = try container.decodeFileDescriptor(forKey: CodingKeys.descriptor)
        // From xpc_fd_dup documentation: If the descriptor could not be created or if the given object was not an XPC
        // file descriptor, -1 is returned.
        if descriptor == -1 {
            let context = DecodingError.Context(codingPath: container.codingPath,
                                                debugDescription: "File descriptor could not be created",
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
        let closeOnEncode = try container.decode(Bool.self, forKey: CodingKeys.closeOnEncode)
        
        self = Self.init(descriptor: descriptor, closeOnEncode: closeOnEncode)
    }
}

// MARK: FileDescriptor

/// Wraps a [`FileDescriptor`](https://developer.apple.com/documentation/system/filedescriptor) such that it can be sent over an XPC
/// connection.
///
/// By default the provided file descriptor will be closed once it has been encoded.
///
/// When creating an ``XPCRoute`` that directly transfers this type as either the message or reply type, `FileDescriptorForXPC` must be the specified type,
/// not `FileDescriptor`. This is not applicable when transferring a type which _contains_ a wrapped file descriptor as one of its properties.
///
/// This property wrapper shares an underlying representation with ``FileHandleForXPC`` and therefore may be used interchangeably between the server and
/// client. However, to make use of such functionality requires routes with identical names and differing message and/or reply types.
@available(macOS 11.0, *)
@propertyWrapper public struct FileDescriptorForXPC {
    public var wrappedValue: FileDescriptor
    fileprivate let closeOnEncode: Bool
    
    public init(wrappedValue: FileDescriptor, closeOnEncode: Bool = true) {
        self.wrappedValue = wrappedValue
        self.closeOnEncode = closeOnEncode
    }
}

@available(macOS 11.0, *)
extension FileDescriptorForXPC: FileDescriptorCodable {
    init(descriptor: CInt, closeOnEncode: Bool) {
        self.wrappedValue = FileDescriptor(rawValue: descriptor)
        self.closeOnEncode = closeOnEncode
    }
    
    var descriptor: CInt {
        wrappedValue.rawValue
    }
    
    func close() throws {
        try wrappedValue.close()
    }
}

// MARK: FileHandle

/// Wraps a [`FileHandle`](https://developer.apple.com/documentation/foundation/filehandle) such that it can be sent over an XPC
/// connection.
///
/// By default the provided file handle will be closed once it has been encoded.
///
/// When creating an ``XPCRoute`` that directly transfers this type as either the message or reply type, `FileHandleForXPC` must be the specified type, not
/// `FileHandle`. This is not applicable when transferring a type which _contains_ a wrapped file handle as one of its properties.
///
/// This property wrapper shares an underlying representation with ``FileDescriptorForXPC`` and therefore may be used interchangeably between the server
/// and client. However, to make use of such functionality requires routes with identical names and differing message and/or reply types.
@propertyWrapper public struct FileHandleForXPC {
    public var wrappedValue: FileHandle
    fileprivate let closeOnEncode: Bool
    
    public init(wrappedValue: FileHandle, closeOnEncode: Bool = true) {
        self.wrappedValue = wrappedValue
        self.closeOnEncode = closeOnEncode
    }
}

extension FileHandleForXPC: FileDescriptorCodable {
    init(descriptor: CInt, closeOnEncode: Bool) {
        self.wrappedValue = FileHandle(fileDescriptor: descriptor)
        self.closeOnEncode = closeOnEncode
    }
    
    var descriptor: CInt {
        wrappedValue.fileDescriptor
    }
    
    func close() throws {
        if #available(macOS 10.15, *) {
            try wrappedValue.close()
        } else {
            wrappedValue.closeFile()
        }
    }
}
