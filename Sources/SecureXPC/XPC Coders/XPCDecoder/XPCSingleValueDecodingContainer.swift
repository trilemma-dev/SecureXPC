//
//  XPCSingleValueDecodingContainer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

fileprivate class XPCSingleValueDecodingContainer: SingleValueDecodingContainer {
	var codingPath: [CodingKey] = []

	private let value: xpc_object_t
	private let type: xpc_type_t

	init(value: xpc_object_t, codingPath: [CodingKey]) {
		self.value = value
		self.type = xpc_get_type(value)
		self.codingPath = codingPath
	}

	func decodeNil() -> Bool {
		return self.type == XPC_TYPE_NULL
	}

	private func decode<T>(xpcType: xpc_type_t, transform: (xpc_object_t) throws -> T) throws -> T {
		return try baseDecode(value: self.value, xpcType: xpcType, transform: transform, codingPath: self.codingPath)
	}

	private func decodeInt<T: FixedWidthInteger & SignedInteger>(_ type: T.Type) throws -> T {
		let transform = intTransform(type, codingPath: self.codingPath)

		return try decode(xpcType: XPC_TYPE_INT64, transform: transform)
	}

	private func decodeUInt<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type) throws -> T {
		let transform = uintTransform(type, codingPath: self.codingPath)

		return try decode(xpcType: XPC_TYPE_UINT64, transform: transform)
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
		return try type.init(from: XPCDecoderImpl(value: self.value, codingPath: self.codingPath))
	}
}
