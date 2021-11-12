//
//  XPCUnkeyedEncodingContainer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

internal class XPCUnkeyedEncodingContainer : UnkeyedEncodingContainer, XPCContainer {
	private var values: [XPCContainer]
	var codingPath: [CodingKey]

	var count: Int {
		self.values.count
	}

	init(codingPath: [CodingKey]) {
		self.codingPath = codingPath
		self.values = [XPCContainer]()
	}

	func encodedValue() throws -> xpc_object_t? {
		let array = xpc_array_create(nil, 0)
		for element in values {
			if let elementValue = try element.encodedValue() {
				xpc_array_append_value(array, elementValue)
			} else {
				let context = EncodingError.Context(codingPath: self.codingPath,
													debugDescription: "This value failed to encode itself",
													underlyingError: nil)
				throw EncodingError.invalidValue(element, context)
			}
		}

		return array
	}

	private func append(_ container: XPCContainer) {
		self.values.append(container)
	}

	private func append(_ value: xpc_object_t) {
		self.append(XPCObject(object: value))
	}

	func encodeNil() {
		self.append(xpc_null_create())
	}

	func encode(_ value: Bool) {
		self.append(xpc_bool_create(value))
	}

	func encode(_ value: String) {
		value.utf8CString.withUnsafeBufferPointer { stringPointer in
			// It is safe to assert the base address will never be nil as the buffer will always have data even if
			// the string is empty
			self.append(xpc_string_create(stringPointer.baseAddress!))
		}
	}

	func encode(_ value: Double) {
		self.append(xpc_double_create(value))
	}

	func encode(_ value: Float) {
		// Float.signalingNaN is not converted to Double.signalingNaN when calling Double(...) with a Float so this
		// needs to be done manually
		let doubleValue = value.isSignalingNaN ? Double.signalingNaN : Double(value)
		self.append(xpc_double_create(doubleValue))
	}

	func encode(_ value: Int) {
		self.append(xpc_int64_create(Int64(value)))
	}

	func encode(_ value: Int8) {
		self.append(xpc_int64_create(Int64(value)))
	}

	func encode(_ value: Int16) {
		self.append(xpc_int64_create(Int64(value)))
	}

	func encode(_ value: Int32) {
		self.append(xpc_int64_create(Int64(value)))
	}

	func encode(_ value: Int64) {
		self.append(xpc_int64_create(value))
	}

	func encode(_ value: UInt) {
		self.append(xpc_uint64_create(UInt64(value)))
	}

	func encode(_ value: UInt8) {
		self.append(xpc_uint64_create(UInt64(value)))
	}

	func encode(_ value: UInt16) {
		self.append(xpc_uint64_create(UInt64(value)))
	}

	func encode(_ value: UInt32) {
		self.append(xpc_uint64_create(UInt64(value)))
	}

	func encode(_ value: UInt64) {
		self.append(xpc_uint64_create(value))
	}

	func encode<T: Encodable>(_ value: T) throws {
		let encoder = XPCEncoderImpl(codingPath: self.codingPath)
		self.append(encoder)

		try value.encode(to: encoder)
	}

	func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
		let nestedContainer = XPCKeyedEncodingContainer<NestedKey>(codingPath: self.codingPath)
		self.append(nestedContainer)

		return KeyedEncodingContainer(nestedContainer)
	}

	func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
		let nestedUnkeyedContainer = XPCUnkeyedEncodingContainer(codingPath: self.codingPath)
		self.append(nestedUnkeyedContainer)

		return nestedUnkeyedContainer
	}

	func superEncoder() -> Encoder {
		let encoder = XPCEncoderImpl(codingPath: self.codingPath)
		self.append(encoder)

		return encoder
	}
}
