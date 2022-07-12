//
//  XPCKeyedDecodingContainer.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

internal class XPCKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
	typealias Key = K

    let userInfo: [CodingUserInfoKey : Any]
	var codingPath = [CodingKey]()
	var allKeys = [K]()

	private let dictionary: [String : xpc_object_t]

    init(value: xpc_object_t, codingPath: [CodingKey], userInfo: [CodingUserInfoKey : Any]) throws {
		if xpc_get_type(value) == XPC_TYPE_DICTIONARY {
			var allKeys = [K]()
			var dictionary = [String : xpc_object_t]()
			xpc_dictionary_apply(value, { (key: UnsafePointer<CChar>, value: xpc_object_t) -> Bool in
				let key = String(cString: key)
				if let codingKey = K(stringValue: key) {
					allKeys.append(codingKey)
					dictionary[key] = value
				}

				return true
			})
			self.allKeys = allKeys
			self.dictionary = dictionary
			self.codingPath = codingPath
            self.userInfo = userInfo
		} else {
			let context = DecodingError.Context(codingPath: self.codingPath,
												debugDescription: "Not a keyed container",
												underlyingError: nil)
			throw DecodingError.typeMismatch(XPCKeyedDecodingContainer.self, context)
		}
	}

	private func value(forKey key: CodingKey) throws -> xpc_object_t {
		if let value = self.dictionary[key.stringValue] {
			return value
		} else {
			let context = DecodingError.Context(codingPath: self.codingPath,
												debugDescription: "Key not found: \(key.stringValue)",
												underlyingError: nil)
			throw DecodingError.keyNotFound(key, context)
		}
	}

	private func decode<T>(key: CodingKey, xpcType: xpc_type_t, transform: (xpc_object_t) throws -> T) throws -> T {
		let value = try value(forKey: key)

		return try baseDecode(value: value, xpcType: xpcType, transform: transform, codingPath: self.codingPath)
	}

	private func decodeInt<T: FixedWidthInteger & SignedInteger>(_ type: T.Type, key: CodingKey) throws -> T {
		let transform = intTransform(type, codingPath: self.codingPath)

		return try decode(key: key, xpcType: XPC_TYPE_INT64, transform: transform)
	}

	private func decodeUInt<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type, key: CodingKey) throws -> T {
		let transform = uintTransform(type, codingPath: self.codingPath)

		return try decode(key: key, xpcType: XPC_TYPE_UINT64, transform: transform)
	}

	func contains(_ key: K) -> Bool {
		return self.dictionary.keys.contains(key.stringValue)
	}

	func decodeNil(forKey key: K) throws -> Bool {
		return xpc_get_type(try value(forKey: key)) == XPC_TYPE_NULL
	}

	func decode(_ type: Bool.Type, forKey key: K) throws -> Bool {
		return try decode(key: key, xpcType: XPC_TYPE_BOOL, transform: xpc_bool_get_value)
	}

	func decode(_ type: String.Type, forKey key: K) throws -> String {
		return try decode(key: key, xpcType: XPC_TYPE_STRING, transform: stringTransform(codingPath: self.codingPath))
	}

	func decode(_ type: Double.Type, forKey key: K) throws -> Double {
		return try decode(key: key, xpcType: XPC_TYPE_DOUBLE, transform: xpc_double_get_value)
	}

	func decode(_ type: Float.Type, forKey key: K) throws -> Float {
		return try decode(key: key, xpcType: XPC_TYPE_DOUBLE, transform: floatTransform)
	}

	func decode(_ type: Int.Type, forKey key: K) throws -> Int {
		return try decodeInt(Int.self, key: key)
	}

	func decode(_ type: Int8.Type, forKey key: K) throws -> Int8 {
		return try decodeInt(Int8.self, key: key)
	}

	func decode(_ type: Int16.Type, forKey key: K) throws -> Int16 {
		return try decodeInt(Int16.self, key: key)
	}

	func decode(_ type: Int32.Type, forKey key: K) throws -> Int32 {
		return try decodeInt(Int32.self, key: key)
	}

	func decode(_ type: Int64.Type, forKey key: K) throws -> Int64 {
		return try decode(key: key, xpcType: XPC_TYPE_INT64, transform: xpc_int64_get_value)
	}

	func decode(_ type: UInt.Type, forKey key: K) throws -> UInt {
		return try decodeUInt(UInt.self, key: key)
	}

	func decode(_ type: UInt8.Type, forKey key: K) throws -> UInt8 {
		return try decodeUInt(UInt8.self, key: key)
	}

	func decode(_ type: UInt16.Type, forKey key: K) throws -> UInt16 {
		return try decodeUInt(UInt16.self, key: key)
	}

	func decode(_ type: UInt32.Type, forKey key: K) throws -> UInt32 {
		return try decodeUInt(UInt32.self, key: key)
	}

	func decode(_ type: UInt64.Type, forKey key: K) throws -> UInt64 {
		return try decode(key: key, xpcType: XPC_TYPE_UINT64, transform: xpc_uint64_get_value)
	}

	func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T : Decodable {
		return try type.init(from: XPCDecoderImpl(value: value(forKey: key),
												  codingPath: self.codingPath + [key],
                                                  userInfo: self.userInfo))
	}

	func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type,
        forKey key: K
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
		return KeyedDecodingContainer(try XPCKeyedDecodingContainer<NestedKey>(value: value(forKey: key),
																			   codingPath: self.codingPath + [key],
                                                                               userInfo: self.userInfo))
	}

	func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
        return try XPCUnkeyedDecodingContainer.containerFor(value: value(forKey: key),
                                                            codingPath: self.codingPath + [key],
                                                            userInfo: self.userInfo)
	}

	func superDecoder() throws -> Decoder {
		if let key = K(stringValue: "super") {
			return try self.superDecoder(forKey: key)
		} else {
			let context = DecodingError.Context(codingPath: self.codingPath,
												debugDescription: "Key could not be created for value: super",
												underlyingError: nil)
			throw DecodingError.valueNotFound(Decoder.self, context)
		}
	}

	func superDecoder(forKey key: K) throws -> Decoder {
		return XPCDecoderImpl(value: try value(forKey: key),
                              codingPath: self.codingPath + [key],
                              userInfo: userInfo)
	}
    
    // MARK: XPC specific decoding
    
    func decodeEndpoint(forKey key: K) throws -> xpc_endpoint_t {
        return try decode(key: key, xpcType: XPC_TYPE_ENDPOINT, transform: {$0})
    }
    
    func decodeFileDescriptor(forKey key: K) throws -> CInt {
        return try decode(key: key, xpcType: XPC_TYPE_FD, transform: xpc_fd_dup)
    }
}
