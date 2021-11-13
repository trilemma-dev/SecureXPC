//
//  XPCKeyedEncodingContainer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

internal class XPCKeyedEncodingContainer<K>: KeyedEncodingContainerProtocol, XPCContainer where K: CodingKey {
	typealias Key = K

	var codingPath: [CodingKey]
	var values: [String : XPCContainer]

	init(codingPath: [CodingKey]) {
		self.codingPath = codingPath
		self.values = [String : XPCContainer]()
	}

	internal func encodedValue() throws -> xpc_object_t? {
		let dictionary = xpc_dictionary_create(nil, nil, 0)
		for (key, value) in self.values {
			try key.utf8CString.withUnsafeBufferPointer { keyPointer in
				if let encodedValue = try value.encodedValue() {
					// It is safe to assert the base address will never be nil as the buffer will always have data even
					// if the string is empty
					xpc_dictionary_set_value(dictionary, keyPointer.baseAddress!, encodedValue)
				} else {
					let context = EncodingError.Context(codingPath: self.codingPath,
														debugDescription: "This value failed to encode itself",
														underlyingError: nil)
					throw EncodingError.invalidValue(value, context)
				}
			}
		}

		return dictionary
	}

	private func setValue(_ container: XPCContainer, forKey key: CodingKey) {
		self.values[key.stringValue] = container
	}

	private func setValue(_ value: xpc_object_t, forKey key: CodingKey) {
		self.setValue(XPCObject(object: value), forKey: key)
	}

	func encodeNil(forKey key: K) throws {
		self.setValue(xpc_null_create(), forKey: key)
	}

	func encode(_ value: Bool, forKey key: K) throws {
		self.setValue(xpc_bool_create(value), forKey: key)
	}

	func encode(_ value: String, forKey key: K) throws {
		value.utf8CString.withUnsafeBufferPointer { stringPointer in
			// It is safe to assert the base address will never be nil as the buffer will always have data even if
			// the string is empty
			self.setValue(xpc_string_create(stringPointer.baseAddress!), forKey: key)
		}
	}

	func encode(_ value: Double, forKey key: K) throws {
		self.setValue(xpc_double_create(value), forKey: key)
	}

	func encode(_ value: Float, forKey key: K) throws {
		// Float.signalingNaN is not converted to Double.signalingNaN when calling Double(...) with a Float so this
		// needs to be done manually
		let doubleValue = value.isSignalingNaN ? Double.signalingNaN : Double(value)
		self.setValue(xpc_double_create(doubleValue), forKey: key)
	}

	func encode(_ value: Int, forKey key: K) throws {
		self.setValue(xpc_int64_create(Int64(value)), forKey: key)
	}

	func encode(_ value: Int8, forKey key: K) throws {
		self.setValue(xpc_int64_create(Int64(value)), forKey: key)
	}

	func encode(_ value: Int16, forKey key: K) throws {
		self.setValue(xpc_int64_create(Int64(value)), forKey: key)
	}

	func encode(_ value: Int32, forKey key: K) throws {
		self.setValue(xpc_int64_create(Int64(value)), forKey: key)
	}

	func encode(_ value: Int64, forKey key: K) throws {
		self.setValue(xpc_int64_create(value), forKey: key)
	}

	func encode(_ value: UInt, forKey key: K) throws {
		self.setValue(xpc_uint64_create(UInt64(value)), forKey: key)
	}

	func encode(_ value: UInt8, forKey key: K) throws {
		self.setValue(xpc_uint64_create(UInt64(value)), forKey: key)
	}

	func encode(_ value: UInt16, forKey key: K) throws {
		self.setValue(xpc_uint64_create(UInt64(value)), forKey: key)
	}

	func encode(_ value: UInt32, forKey key: K) throws {
		self.setValue(xpc_uint64_create(UInt64(value)), forKey: key)
	}

	func encode(_ value: UInt64, forKey key: K) throws {
		self.setValue(xpc_uint64_create(value), forKey: key)
	}

	func encode<T>(_ value: T, forKey key: K) throws where T : Encodable {
		let encoder = XPCEncoderImpl(codingPath: self.codingPath + [key])
		self.setValue(encoder, forKey: key)

		try value.encode(to: encoder)
	}

	func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
		let nestedContainer = XPCKeyedEncodingContainer<NestedKey>(codingPath: self.codingPath + [key])
		self.setValue(nestedContainer, forKey: key)

		return KeyedEncodingContainer(nestedContainer)
	}

	func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
		let nestedUnkeyedContainer = XPCUnkeyedEncodingContainer(codingPath: self.codingPath + [key])
		self.setValue(nestedUnkeyedContainer, forKey: key)

		return nestedUnkeyedContainer
	}

	private struct SuperKey: CodingKey {
		var stringValue: String
		var intValue: Int?

		init() {
			self.stringValue = "super"
			self.intValue = nil
		}

		init?(stringValue: String) {
			self.stringValue = "super"
			self.intValue = nil
		}

		init?(intValue: Int) {
			self.stringValue = "super"
			self.intValue = nil
		}
	}

	func superEncoder() -> Encoder {
		let key = SuperKey()
		let encoder = XPCEncoderImpl(codingPath: self.codingPath + [key])
		self.setValue(encoder, forKey: key)

		return encoder
	}

	func superEncoder(forKey key: K) -> Encoder {
		let encoder = XPCEncoderImpl(codingPath: self.codingPath + [key])
		self.setValue(encoder, forKey: key)

		return encoder
	}
}

