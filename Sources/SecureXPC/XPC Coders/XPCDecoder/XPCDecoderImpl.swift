//
//  XPCDecoderImpl.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

internal class XPCDecoderImpl: Decoder {
	var codingPath = [CodingKey]()
    let userInfo: [CodingUserInfoKey : Any]
	private let value: xpc_object_t

    init(value: xpc_object_t, codingPath: [CodingKey], userInfo: [CodingUserInfoKey : Any]) {
		self.value = value
		self.codingPath = codingPath
        self.userInfo = userInfo
	}
    
    // Internal implementation so that XPC-specific functions of the container can be accessed
    internal func xpcContainer<Key>(
        keyedBy type: Key.Type
    ) throws -> XPCKeyedDecodingContainer<Key> where Key : CodingKey {
        try XPCKeyedDecodingContainer(value: self.value, codingPath: self.codingPath, userInfo: self.userInfo)
    }

	func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        KeyedDecodingContainer(try XPCKeyedDecodingContainer(value: self.value,
                                                             codingPath: self.codingPath,
                                                             userInfo: self.userInfo))
	}

	func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        try XPCUnkeyedDecodingContainer.containerFor(value: self.value,
                                                     codingPath: self.codingPath,
                                                     userInfo: self.userInfo)
	}

	func singleValueContainer() throws -> SingleValueDecodingContainer {
        XPCSingleValueDecodingContainer(value: self.value,
                                        codingPath: self.codingPath,
                                        userInfo: self.userInfo)
	}
}
