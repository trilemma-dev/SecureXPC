//
//  XPCEncoderImpl.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

internal class XPCEncoderImpl: Encoder, XPCContainer {
	var codingPath: [CodingKey]
	private var container: XPCContainer?

	var userInfo: [CodingUserInfoKey : Any] {
		return [:]
	}

	init(codingPath: [CodingKey]) {
		self.codingPath = codingPath
	}

	func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
		let container = XPCKeyedEncodingContainer<Key>(codingPath: self.codingPath)
		self.container = container

		return KeyedEncodingContainer(container)
	}

	func unkeyedContainer() -> UnkeyedEncodingContainer {
		let container = XPCUnkeyedEncodingContainer(codingPath: self.codingPath)
		self.container = container

		return container
	}

	func singleValueContainer() -> SingleValueEncodingContainer {
		let container = XPCSingleValueEncodingContainer(codingPath: self.codingPath)
		self.container = container

		return container
	}

	fileprivate func encodedValue() throws -> xpc_object_t? {
		return try container?.encodedValue()
	}
}
