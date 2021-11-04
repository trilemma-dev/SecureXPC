//
//  XPCEncoder.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// Package internal entry point to encoding payloads, routes, and errors to XPC dictionaries
enum XPCEncoder {
    
    /// Encodes the value as an XPC dictionary.
    ///
    /// - Parameters:
    ///  - _: The value to be encoded
    /// - Throws: If unable to encode the value.
    /// - Returns: Value as an XPC dictionary.
    static func encode<T: Encodable>(_ value: T) throws -> xpc_object_t {
        let encoder = XPCEncoderImpl(codingPath: [CodingKey]())
        try value.encode(to: encoder)
        
        guard let encodedValue = try encoder.encodedValue() else {
            let context = EncodingError.Context(codingPath: [CodingKey](),
                                                debugDescription: "value failed to encode itself",
                                                underlyingError: nil)
            throw EncodingError.invalidValue(value, context)
        }
        
        return encodedValue
    }
}

fileprivate protocol XPCContainer {
    func encodedValue() throws -> xpc_object_t?
}

fileprivate struct XPCObject: XPCContainer {
    let object: xpc_object_t
    
    func encodedValue() throws -> xpc_object_t? {
        return object
    }
}

fileprivate class XPCEncoderImpl: Encoder, XPCContainer {
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

fileprivate class XPCSingleValueEncodingContainer: SingleValueEncodingContainer, XPCContainer {
    private var value: XPCContainer?
    var codingPath: [CodingKey]
    
    init(codingPath: [CodingKey]) {
        self.codingPath = codingPath
    }
    
    func encodedValue() throws -> xpc_object_t? {
        return try value?.encodedValue()
    }
    
    private func setValue(_ container: XPCContainer) {
        self.value = container
    }
    
    private func setValue(_ value: xpc_object_t) {
        self.setValue(XPCObject(object: value))
    }
    
    func encodeNil() {
        self.setValue(xpc_null_create())
    }
    
    func encode(_ value: Bool) {
        self.setValue(xpc_bool_create(value))
    }
    
    func encode(_ value: String) {
        value.utf8CString.withUnsafeBufferPointer { stringPointer in
            // It is safe to assert the base address will never be nil as the buffer will always have data even if
            // the string is empty
            self.setValue(xpc_string_create(stringPointer.baseAddress!))
       }
    }
    
    func encode(_ value: Double) {
        self.setValue(xpc_double_create(value))
    }
    
    func encode(_ value: Float) {
        self.setValue(xpc_double_create(Double(value)))
    }
    
    func encode(_ value: Int) {
        self.setValue(xpc_int64_create(Int64(value)))
    }
    
    func encode(_ value: Int8) {
        self.setValue(xpc_int64_create(Int64(value)))
    }
    
    func encode(_ value: Int16) {
        self.setValue(xpc_int64_create(Int64(value)))
    }
    
    func encode(_ value: Int32) {
        self.setValue(xpc_int64_create(Int64(value)))
    }
    
    func encode(_ value: Int64) {
        self.setValue(xpc_int64_create(value))
    }
    
    func encode(_ value: UInt) {
        self.setValue(xpc_uint64_create(UInt64(value)))
    }
    
    func encode(_ value: UInt8) {
        self.setValue(xpc_uint64_create(UInt64(value)))
    }
    
    func encode(_ value: UInt16) {
        self.setValue(xpc_uint64_create(UInt64(value)))
    }
    
    func encode(_ value: UInt32) {
        self.setValue(xpc_uint64_create(UInt64(value)))
    }
    
    func encode(_ value: UInt64) {
        self.setValue(xpc_uint64_create(value))
    }
    
    func encode<T: Encodable>(_ value: T) throws {
        let encoder = XPCEncoderImpl(codingPath: self.codingPath)
        self.setValue(encoder)
        
        try value.encode(to: encoder)
    }
}

fileprivate class XPCUnkeyedEncodingContainer : UnkeyedEncodingContainer, XPCContainer {
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
        self.append(xpc_double_create(Double(value)))
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

fileprivate class XPCKeyedEncodingContainer<K>: KeyedEncodingContainerProtocol, XPCContainer where K: CodingKey {
    typealias Key = K

    var codingPath: [CodingKey]
    var values: [String : XPCContainer]
    
    init(codingPath: [CodingKey]) {
        self.codingPath = codingPath
        self.values = [String : XPCContainer]()
    }
    
    fileprivate func encodedValue() throws -> xpc_object_t? {
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
        self.setValue(xpc_double_create(Double(value)), forKey: key)
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
