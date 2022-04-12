//
//  XPCFileDescriptorContainer.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-04-12
//

import Foundation
import System

/// A container for a file descriptor which can be sent over an XPC connection.
///
/// Any initializer may be used in combination with any `duplicate` function. For example, it is valid to create a container using
/// ``init(descriptor:closeDescriptor:)-5b3wo``, send it over an XPC connection, and then on the receiving side call
/// ``duplicateAsFileHandle()``.
///
/// > Warning: While ``XPCFileDescriptorContainer`` conforms to `Codable` it can only be encoded and decoded by the `SecureXPC` framework.
///
/// ## Topics
/// ### Creating a Container
/// - ``init(descriptor:closeDescriptor:)-5b3wo``
/// - ``init(handle:closeHandle:)``
/// - ``init(descriptor:closeDescriptor:)-8kiiv``
///
/// ### Duplicating
/// - ``duplicateAsNativeDescriptor()``
/// - ``duplicateAsFileHandle()``
/// - ``duplicateAsFileDescriptor()``
public struct XPCFileDescriptorContainer {
    
    /// Errors related to boxing or duplicating file descriptors.
    public enum XPCFileDescriptorContainerError: Error {
        /// The provided value is not a valid file descriptor, including because it has already been closed.
        case invalidFileDescriptor
    }
    
    private let xpcEncodedForm: xpc_object_t
    
    /// Boxes the provided native file descriptor.
    ///
    /// - Parameters:
    ///   - descriptor: The descriptor to be boxed.
    ///   - closeDescriptor: If set to `true`, `descriptor` will be closed if this initializer succesfully completes.
    public init(descriptor: Int32, closeDescriptor: Bool) throws {
        guard let xpcEncodedForm = xpc_fd_create(descriptor) else {
            throw XPCFileDescriptorContainerError.invalidFileDescriptor
        }
        self.xpcEncodedForm = xpcEncodedForm
        
        if closeDescriptor {
            close(descriptor)
        }
    }
    
    /// Boxes the provided [`FileHandle`](https://developer.apple.com/documentation/foundation/filehandle).
    ///
    /// - Parameters:
    ///   - handle: The file handle to be boxed.
    ///   - closeHandle: If set to `true`, `handler` will be closed if this initializer succesfully completes.
    public init(handle: FileHandle, closeHandle: Bool) throws {
        guard let xpcEncodedForm = xpc_fd_create(handle.fileDescriptor) else {
            throw XPCFileDescriptorContainerError.invalidFileDescriptor
        }
        self.xpcEncodedForm = xpcEncodedForm
        
        if closeHandle {
            if #available(macOS 10.15, *) {
                try handle.close()
            } else {
                handle.closeFile()
            }
        }
    }
    
    /// Boxes the provided [`FileDescriptor`](https://developer.apple.com/documentation/system/filedescriptor).
    ///
    /// - Parameters:
    ///   - descriptor: The descriptor to be boxed.
    ///   - closeDescriptor: If set to `true`, `descriptor` will be closed if this initializer succesfully completes.
    @available(macOS 11.0, *)
    public init(descriptor: FileDescriptor, closeDescriptor: Bool) throws {
        guard let xpcEncodedForm = xpc_fd_create(descriptor.rawValue) else {
            throw XPCFileDescriptorContainerError.invalidFileDescriptor
        }
        self.xpcEncodedForm = xpcEncodedForm
        
        if closeDescriptor {
            try descriptor.close()
        }
    }
    
    /// Returns a file descriptor equivalent to the one originally boxed.
    ///
    /// This function may be called multiple times, but each time it will return a different file descriptor. The returned descriptors will be equivalent, as though they
    /// had been created by
    /// [dup(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/dup2.2.html).
    ///
    /// > Important: The caller is responsible for calling
    /// [close(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/close.2.html#//apple_ref/doc/man/2/close)
    /// on the returned descriptor.
    public func duplicateAsNativeDescriptor() throws -> Int32 {
        let fd = xpc_fd_dup(self.xpcEncodedForm)
        // From xpc_fd_dup documentation:
        //     If the descriptor could not be created or if the given object was not an XPC file descriptor, -1 is
        //     returned.
        if fd == -1 {
            throw XPCFileDescriptorContainerError.invalidFileDescriptor
        }
        
        return fd
    }
    
    /// Returns a [`FileHandle`](https://developer.apple.com/documentation/foundation/filehandle) equivalent to the one originally boxed.
    ///
    /// This function may be called multiple times, but each time it will return a different file handle that is equivalent.
    ///
    /// > Important: The caller is responsible for calling
    /// [`close()`](https://developer.apple.com/documentation/foundation/filehandle/3172525-close) or
    /// [`closeFile()`](https://developer.apple.com/documentation/foundation/filehandle/1413393-closefile).
    public func duplicateAsFileHandle() throws -> FileHandle {
        FileHandle(fileDescriptor: try duplicateAsNativeDescriptor())
    }
    
    /// Returns a [`FileDescriptor`](https://developer.apple.com/documentation/system/filedescriptor) equivalent to the one originally
    /// boxed.
    ///
    /// This function may be called multiple times, but each time it will return a different file descriptor. The returned descriptors will be equivalent, as though they
    /// had been created by
    ///  [`duplicate(as:retryoninterrupt:)`](https://developer.apple.com/documentation/system/filedescriptor/duplicate(as:retryoninterrupt:)).
    ///
    /// > Important: The caller is responsible for calling
    /// [`close()`](https://developer.apple.com/documentation/system/filedescriptor/close()) or
    /// [`closeAfter(_:)`](https://developer.apple.com/documentation/system/filedescriptor/closeafter(_:)) on the returned descriptor.
    @available(macOS 11.0, *)
    public func duplicateAsFileDescriptor() throws -> FileDescriptor {
        FileDescriptor(rawValue: try duplicateAsNativeDescriptor())
    }
}

// MARK: Codable

extension XPCFileDescriptorContainer: Encodable {
    public func encode(to encoder: Encoder) throws {
        guard let xpcEncoder = encoder as? XPCEncoderImpl else {
            throw XPCCoderError.onlyEncodableBySecureXPCFramework
        }
        
        let container = xpcEncoder.xpcSingleValueContainer()
        container.setAlreadyEncodedValue(self.xpcEncodedForm)
    }
}

extension XPCFileDescriptorContainer: Decodable {
    public init(from decoder: Decoder) throws {
        guard let xpcDecoder = decoder as? XPCDecoderImpl else {
            throw XPCCoderError.onlyDecodableBySecureXPCFramework
        }
        
        let container = xpcDecoder.xpcSingleValueContainer()
        self.xpcEncodedForm = try container.accessAsEncodedValue(xpcType: XPC_TYPE_FD)
    }
}
