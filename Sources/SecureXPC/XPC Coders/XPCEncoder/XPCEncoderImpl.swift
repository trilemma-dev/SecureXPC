//
//  XPCEncoderImpl.swift
//  SecureXPC
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
    
    static func asXPCEncoderImpl(_ encoder: Encoder) throws -> XPCEncoderImpl {
        guard let xpcEncoder = encoder as? XPCEncoderImpl else {
            throw XPCCoderError.onlyEncodableBySecureXPC
        }
        
        return xpcEncoder
    }
    
    // Internal implementation so that XPC-specific functions of the container can be accessed
    internal func xpcContainer<Key>(keyedBy type: Key.Type) -> XPCKeyedEncodingContainer<Key> where Key: CodingKey {
        let container = XPCKeyedEncodingContainer<Key>(codingPath: self.codingPath)
        self.container = container
        
        return container
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
    
    // Internal implementation so that XPC-specific functions of the container can be accessed
    func xpcSingleValueContainer() -> XPCSingleValueEncodingContainer {
        let container = XPCSingleValueEncodingContainer(codingPath: self.codingPath)
        self.container = container

        return container
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        return xpcSingleValueContainer()
    }

	internal func encodedValue() throws -> xpc_object_t? {
		return try container?.encodedValue()
	}
}
