//
//  ArrayOptimizedForXPC.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-19
//

import Foundation

/// Wraps an array to optimize how it is sent over an XPC connection.
///
/// Arrays of the following type are automatically supported by this property wrapper: `Bool`, `Double`, `Float`, `UInt`, `UInt8`, `UInt16`, `UInt32`,
/// `UInt64`, `Int`, `Int8`, `Int16`, `Int32`, and `Int64`. You may add support for your own trivial types by having them conform to ``Trivial``.
///
/// Usage of this property wrapper is never required and has no benefit when the array is either the message or reply type for an ``XPCRoute``.  When transferring
/// a type which _contains_ an array property it is more efficient both in runtime and memory usage to wrap it using this property wrapper.
@propertyWrapper public struct ArrayOptimizedForXPC<Element: Trivial & Codable> {
    // Note: There's no actual need for Element to conform to Codable, but doing so provides consistency between arrays
    // which are wrapped with this property wrapper vs those that are not. Also it's easy for most trivial types to
    // become Codable conforming simplying by declaring conformance; the compiler will autogenerate the implementation.
    
    public var wrappedValue: [Element]
    
    public init(wrappedValue: [Element]) {
        self.wrappedValue = wrappedValue
    }
}

// MARK: Codable

extension ArrayOptimizedForXPC: Encodable {
    public func encode(to encoder: Encoder) throws {
        let xpcEncoder = try XPCEncoderImpl.asXPCEncoderImpl(encoder)
        guard let data = encodeArrayAsData(value: self.wrappedValue) else {
            let debugDescription = "Unable to encode \(self.wrappedValue.self) to XPC data represetation"
            let context = EncodingError.Context(codingPath: encoder.codingPath,
                                                debugDescription: debugDescription,
                                                underlyingError: nil)
            throw EncodingError.invalidValue(self.wrappedValue, context)
        }
        
        xpcEncoder.xpcSingleValueContainer().setAlreadyEncodedValue(data)
    }
}

extension ArrayOptimizedForXPC: Decodable {
    public init(from decoder: Decoder) throws {
        let xpcDecoder = try XPCDecoderImpl.asXPCDecoderImpl(decoder)
        let container = xpcDecoder.xpcSingleValueContainer()
        guard let array = decodeDataAsArray(arrayType: [Element].self, arrayAsData: container.value) else {
            let debugDescription = "Unable to decode \(container.value.description) to an array of type \(Element.self)"
            let context = DecodingError.Context(codingPath: container.codingPath,
                                                debugDescription: debugDescription,
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
        
        self.wrappedValue = array
    }
}

// MARK: Helper functions

// Exposes a small portion of Array without needing to know the type of the array
private protocol TypeErasedArray {
    static var elementType: Any.Type { get }
    static var elementStride: Int { get }
    var elementCount: Int { get }
    func withUnsafePointer<R>(_ body: (UnsafeRawPointer?) throws -> R) rethrows -> R
    init(pointer: UnsafeRawPointer, count: Int)
}

extension Array: TypeErasedArray {
    static var elementType: Any.Type {
        Element.self
    }
    
    static var elementStride: Int {
        MemoryLayout<Element>.stride
    }
    
    var elementCount: Int {
        self.count
    }
    
    func withUnsafePointer<R>(_ body: (UnsafeRawPointer?) throws -> R) rethrows -> R {
        // Only trivial types (also known as "Plain Old Data" or "POD" for short) can have their data accessed safely
        // via withUnsafeBytes for an array (this is documented behavior for withUnsafeBytes)
        guard _isPOD(Element.self) else {
            fatalError("\(Element.self) is not trivial")
        }
        
        return try self.withUnsafeBytes{ try body($0.baseAddress) }
    }
    
    init(pointer: UnsafeRawPointer, count: Int) {
        let boundPointer = pointer.bindMemory(to: Element.self, capacity: count)
        let bufferPointer = UnsafeBufferPointer(start: boundPointer, count: count)
        self = Self.init(bufferPointer)
    }
}

internal func encodeArrayAsData(value: Any) -> xpc_object_t? {
    guard let array = value as? TypeErasedArray,
          type(of: array).elementType is Trivial.Type,
          type(of: array).elementType is Codable.Type else {
        return nil
    }
    
    return array.withUnsafePointer { xpc_data_create($0, array.elementCount * type(of: array).elementStride) }
}

internal func decodeDataAsArray<T>(arrayType: T.Type, arrayAsData: xpc_object_t) -> T? {
    guard xpc_get_type(arrayAsData) == XPC_TYPE_DATA else {
        return nil
    }
    guard let pointer = xpc_data_get_bytes_ptr(arrayAsData) else {
        return nil
    }
    guard let arrayType = arrayType as? TypeErasedArray.Type,
          arrayType.elementType is Trivial.Type,
          arrayType.elementType is Codable.Type else {
        return nil
    }
    
    return arrayType.init(pointer: pointer, count: xpc_data_get_length(arrayAsData) / arrayType.elementStride) as? T
}
