//
//  ArrayOptimizedForXPC.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-19
//

import Foundation

/// Wraps an array to optimize how it is sent over an XPC connection.
///
/// Arrays of the following type are supported by this property wrapper: `Bool`, `Double`, `Float`, `UInt`, `UInt8`, `UInt16`, `UInt32`, `UInt64`,
/// `Int`, `Int8`, `Int16`, `Int32`, and `Int64`.
///
/// Usage of this property wrapper is never required and has no benefit when the array is either the message or reply type for an ``XPCRoute``.  When transferring
/// a type which _contains_ an array property it is more efficient both in runtime and memory usage to wrap it using this property wrapper.
@propertyWrapper public struct ArrayOptimizedForXPC<Element: XPCOptimizableArrayElement> {
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

internal func encodeArrayAsData(value: Any) -> xpc_object_t? {
    func directEncodeArray<E>(_ array: [E]) -> xpc_object_t {
        array.withUnsafeBytes { xpc_data_create($0.baseAddress, array.count * MemoryLayout<E>.stride) }
    }
    
    if let array = value as? [Bool] {   return directEncodeArray(array) }
    if let array = value as? [Double] { return directEncodeArray(array) }
    if let array = value as? [Float] {  return directEncodeArray(array) }
    if let array = value as? [UInt] {   return directEncodeArray(array) }
    if let array = value as? [UInt8] {  return directEncodeArray(array) }
    if let array = value as? [UInt16] { return directEncodeArray(array) }
    if let array = value as? [UInt32] { return directEncodeArray(array) }
    if let array = value as? [UInt64] { return directEncodeArray(array) }
    if let array = value as? [Int] {    return directEncodeArray(array) }
    if let array = value as? [Int8] {   return directEncodeArray(array) }
    if let array = value as? [Int16] {  return directEncodeArray(array) }
    if let array = value as? [Int32] {  return directEncodeArray(array) }
    if let array = value as? [Int64] {  return directEncodeArray(array) }
    
    return nil
}

internal func decodeDataAsArray<T>(arrayType: T.Type, arrayAsData: xpc_object_t) -> T? {
    func directDecodeArray<E>(_ pointer: UnsafeRawPointer, length: Int, type: E.Type) -> [E] {
        let count = length / MemoryLayout<E>.stride
        let boundPointer = pointer.bindMemory(to: E.self, capacity: count)
        let bufferPoint = UnsafeBufferPointer(start: boundPointer, count: count)
        
        return Array<E>(bufferPoint)
    }
    
    guard xpc_get_type(arrayAsData) == XPC_TYPE_DATA else {
        return nil
    }
    
    guard let pointer = xpc_data_get_bytes_ptr(arrayAsData) else {
        return nil
    }
    let length = xpc_data_get_length(arrayAsData)
    
    if arrayType == [Bool].self {   return directDecodeArray(pointer, length: length, type: Bool.self) as? T }
    if arrayType == [Double].self { return directDecodeArray(pointer, length: length, type: Double.self) as? T }
    if arrayType == [Float].self {  return directDecodeArray(pointer, length: length, type: Float.self) as? T }
    if arrayType == [UInt].self {   return directDecodeArray(pointer, length: length, type: UInt.self) as? T }
    if arrayType == [UInt8].self {  return directDecodeArray(pointer, length: length, type: UInt8.self) as? T }
    if arrayType == [UInt16].self { return directDecodeArray(pointer, length: length, type: UInt16.self) as? T }
    if arrayType == [UInt32].self { return directDecodeArray(pointer, length: length, type: UInt32.self) as? T }
    if arrayType == [UInt64].self { return directDecodeArray(pointer, length: length, type: UInt64.self) as? T }
    if arrayType == [Int].self {    return directDecodeArray(pointer, length: length, type: Int.self) as? T }
    if arrayType == [Int8].self {   return directDecodeArray(pointer, length: length, type: Int8.self) as? T }
    if arrayType == [Int16].self {  return directDecodeArray(pointer, length: length, type: Int16.self) as? T }
    if arrayType == [Int32].self {  return directDecodeArray(pointer, length: length, type: Int32.self) as? T }
    if arrayType == [Int64].self {  return directDecodeArray(pointer, length: length, type: Int64.self) as? T }
    
    return nil
}

// MARK: type constraining protocol

/// Constrains the array elements supported by ``ArrayOptimizedForXPC``.
///
/// >Warning: Do not implement this protocol.
public protocol XPCOptimizableArrayElement: Codable { }

extension Bool: XPCOptimizableArrayElement {}
extension Double: XPCOptimizableArrayElement {}
extension Float: XPCOptimizableArrayElement {}
extension UInt: XPCOptimizableArrayElement {}
extension UInt8: XPCOptimizableArrayElement {}
extension UInt16: XPCOptimizableArrayElement {}
extension UInt32: XPCOptimizableArrayElement {}
extension UInt64: XPCOptimizableArrayElement {}
extension Int: XPCOptimizableArrayElement {}
extension Int8: XPCOptimizableArrayElement {}
extension Int16: XPCOptimizableArrayElement {}
extension Int32: XPCOptimizableArrayElement {}
extension Int64: XPCOptimizableArrayElement {}
