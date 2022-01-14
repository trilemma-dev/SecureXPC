//
//  XPCDecoderImpl.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

internal class XPCDecoderImpl: Decoder {
	var codingPath = [CodingKey]()

	let userInfo = [CodingUserInfoKey : Any]()

	private let value: xpc_object_t


	init(value: xpc_object_t, codingPath: [CodingKey]) {
		self.value = value
		self.codingPath = codingPath
	}
    
    // Internal implementation so that XPC-specific functions of the container can be accessed
    internal func xpcContainer<Key>(
        keyedBy type: Key.Type
    ) throws -> XPCKeyedDecodingContainer<Key> where Key : CodingKey {
        return try XPCKeyedDecodingContainer(value: self.value, codingPath: self.codingPath)
    }

	func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
		return KeyedDecodingContainer(try XPCKeyedDecodingContainer(value: self.value, codingPath: self.codingPath))
	}

	func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return try XPCUnkeyedDecodingContainer.containerFor(value: self.value, codingPath: self.codingPath)
	}

	func singleValueContainer() throws -> SingleValueDecodingContainer {
		return XPCSingleValueDecodingContainer(value: self.value, codingPath: self.codingPath)
	}
}
