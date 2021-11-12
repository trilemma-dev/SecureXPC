//
//  XPCUnkeyedDecodingContainer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

fileprivate class XPCUnkeyedDecodingContainer: UnkeyedDecodingContainer {
	private let array: [xpc_object_t]
	var currentIndex: Int
	var codingPath = [CodingKey]()

	init(value: xpc_object_t, codingPath: [CodingKey]) throws {
		if xpc_get_type(value) == XPC_TYPE_ARRAY {
			var array = [xpc_object_t]()
			let count = xpc_array_get_count(value)
			for index in 0..<count {
				array.append(xpc_array_get_value(value, index))
			}
			self.array = array
			self.currentIndex = 0
			self.codingPath = codingPath
		} else {
			let context = DecodingError.Context(codingPath: [],
												debugDescription: "Not an array",
												underlyingError: nil)
			throw DecodingError.typeMismatch(XPCUnkeyedDecodingContainer.self, context)
		}
	}

	var count: Int? {
		self.array.count
	}

	var isAtEnd: Bool {
		self.currentIndex >= self.array.count
	}

	private func nextElement(_ type: Any.Type) throws -> xpc_object_t {
		if isAtEnd {
			let context = DecodingError.Context(codingPath: self.codingPath,
												debugDescription: "No more elements remaining to decode",
												underlyingError: nil)
			throw DecodingError.valueNotFound(type, context)
		}

		return self.array[self.currentIndex]
	}

	private func decode<T>(xpcType: xpc_type_t, transform: (xpc_object_t) throws -> T) throws -> T {
		let decodedElement = try baseDecode(value: try nextElement(T.self),
											xpcType: xpcType,
											transform: transform,
											codingPath: self.codingPath)
		currentIndex += 1

		return decodedElement
	}

	private func decodeInt<T: FixedWidthInteger & SignedInteger>(_ type: T.Type) throws -> T {
		let transform = intTransform(type, codingPath: self.codingPath)

		return try decode(xpcType: XPC_TYPE_INT64, transform: transform)
	}

	private func decodeUInt<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type) throws -> T {
		let transform = uintTransform(type, codingPath: self.codingPath)

		return try decode(xpcType: XPC_TYPE_UINT64, transform: transform)
	}

	func decodeNil() throws -> Bool {
		// From protocol documentation: If the value is not null, does not increment currentIndex
		let element = try nextElement(Never.self)
		let isNull = xpc_get_type(element) == XPC_TYPE_NULL
		if isNull {
			currentIndex += 1
		}

		return isNull
	}

	func decode(_ type: Bool.Type) throws -> Bool {
		return try decode(xpcType: XPC_TYPE_BOOL, transform: xpc_bool_get_value)
	}

	func decode(_ type: String.Type) throws -> String {
		return try decode(xpcType: XPC_TYPE_STRING, transform: stringTransform(codingPath: self.codingPath))
	}

	func decode(_ type: Double.Type) throws -> Double {
		return try decode(xpcType: XPC_TYPE_DOUBLE, transform: xpc_double_get_value)
	}

	func decode(_ type: Float.Type) throws -> Float {
		return try decode(xpcType: XPC_TYPE_DOUBLE, transform: floatTransform)
	}

	func decode(_ type: Int.Type) throws -> Int {
		return try decodeInt(Int.self)
	}

	func decode(_ type: Int8.Type) throws -> Int8 {
		return try decodeInt(Int8.self)
	}

	func decode(_ type: Int16.Type) throws -> Int16 {
		return try decodeInt(Int16.self)
	}

	func decode(_ type: Int32.Type) throws -> Int32 {
		return try decodeInt(Int32.self)
	}

	func decode(_ type: Int64.Type) throws -> Int64 {
		return try decode(xpcType: XPC_TYPE_INT64, transform: xpc_int64_get_value)
	}

	func decode(_ type: UInt.Type) throws -> UInt {
		return try decodeUInt(UInt.self)
	}

	func decode(_ type: UInt8.Type) throws -> UInt8 {
		return try decodeUInt(UInt8.self)
	}

	func decode(_ type: UInt16.Type) throws -> UInt16 {
		return try decodeUInt(UInt16.self)
	}

	func decode(_ type: UInt32.Type) throws -> UInt32 {
		return try decodeUInt(UInt32.self)
	}

	func decode(_ type: UInt64.Type) throws -> UInt64 {
		return try decode(xpcType: XPC_TYPE_UINT64, transform: xpc_uint64_get_value)
	}

	func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
		let decodedElement = try T(from: XPCDecoderImpl(value: try nextElement(type), codingPath: self.codingPath))
		currentIndex += 1

		return decodedElement
	}

	func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
		let value = try nextElement(UnkeyedDecodingContainer.self)
		let container = KeyedDecodingContainer<NestedKey>(try XPCKeyedDecodingContainer(value: value,
																						codingPath: self.codingPath))
		currentIndex += 1

		return container
	}

	func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
		let container = try XPCUnkeyedDecodingContainer(value: try nextElement(UnkeyedDecodingContainer.self),
														codingPath: self.codingPath)
		currentIndex += 1

		return container
	}

	func superDecoder() throws -> Decoder {
		let decoder = XPCDecoderImpl(value: try nextElement(Decoder.self), codingPath: self.codingPath)
		currentIndex += 1

		return decoder
	}
}
