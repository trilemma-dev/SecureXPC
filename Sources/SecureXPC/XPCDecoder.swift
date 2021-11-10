//
//  XPCDecoder.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// Package internal entry point to decoding as well as checking for the presence of keys in an XPC dictionary.
enum XPCDecoder {
    
    /// Whether the provided XPC dictionary contains the key.
    ///
    /// - Parameters:
    ///   - _:  The key to be checked.
    ///   - dictionary: The XPC dictionary to check for the XPC key in.
    /// - Throws: If the value provided was not an XPC dictionary.
    /// - Returns: Whether the key is contained in the provided dictionary.
    static func containsKey(_ key: XPCDictionaryKey, inDictionary dictionary: xpc_object_t) throws -> Bool {
        try checkXPCDictionary(object: dictionary)
        
        return xpc_dictionary_get_value(dictionary, key) != nil
    }
    
    /// Decodes the value corresponding to the key in the XPC dictionary.
    ///
    /// - Parameters:
    ///  - _: The type to decode the XPC representation to.
    ///  - from: The XPC dictionary containing the value to decode.
    ///  - forKey: The key of the value in the XPC dictionary.
    /// - Throws: If `from` isn't a dictionary, the `key` isn't present in the dictionary, or the decoding fails.
    /// - Returns: An instance of the provided type corresponding to the contents of the value for the provided key.
    static func decode<T: Decodable>(_ type: T.Type,
                                     from dictionary: xpc_object_t,
                                     forKey key: XPCDictionaryKey) throws -> T {
        try checkXPCDictionary(object: dictionary)
        
        if let value = xpc_dictionary_get_value(dictionary, key) {
            return try decode(type, object: value)
        } else {
            // Ideally this would throw DecodingError.keyNotFound(...) but that requires providing a CodingKey
            // and there isn't one yet
            let context = DecodingError.Context(codingPath: [CodingKey](),
                                                debugDescription: "Key not present: \(key)",
                                                underlyingError: nil)
            throw DecodingError.valueNotFound(type, context)
        }
    }
    
    /// Decodes the XPC object.
    ///
    /// - Parameters:
    ///  - _: The type to decode the XPC representation to.
    ///  - object: The XPC object.
    /// - Throws: If decoding fails.
    /// - Returns: An instance of the provided type corresponding to the object.
    static func decode<T: Decodable>(_ type: T.Type, object: xpc_object_t) throws -> T {
        return try T(from: XPCDecoderImpl(value: object, codingPath: [CodingKey]()))
    }
    
    /// Throws an error if the provided XPC object is not an XPC dictionary.
    private static func checkXPCDictionary(object: xpc_object_t) throws {
        let type = xpc_get_type(object)
        if type != XPC_TYPE_DICTIONARY {
            let context = DecodingError.Context(codingPath: [CodingKey](),
                                                debugDescription: "XPC dictionary required; was \(type.description)",
                                                underlyingError: nil)
            throw DecodingError.typeMismatch(xpc_object_t.self, context)
        }
    }
}

fileprivate class XPCDecoderImpl: Decoder {
    var codingPath = [CodingKey]()
    
    let userInfo = [CodingUserInfoKey : Any]()
    
    private let value: xpc_object_t
    
    
    init(value: xpc_object_t, codingPath: [CodingKey]) {
        self.value = value
        self.codingPath = codingPath
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(try XPCKeyedDecodingContainer(value: self.value, codingPath: self.codingPath))
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return try XPCUnkeyedDecodingContainer(value: self.value, codingPath: self.codingPath)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return XPCSingleValueDecodingContainer(value: self.value, codingPath: self.codingPath)
    }
}

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

fileprivate class XPCKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K
    
    var codingPath = [CodingKey]()
    var allKeys = [K]()
    
    private let dictionary: [String : xpc_object_t]
    
    init(value: xpc_object_t, codingPath: [CodingKey]) throws {
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
                                                  codingPath: self.codingPath + [key]))
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        return KeyedDecodingContainer(try XPCKeyedDecodingContainer<NestedKey>(value: value(forKey: key),
                                                                               codingPath: self.codingPath + [key]))
    }
    
    func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
        return try XPCUnkeyedDecodingContainer(value: value(forKey: key),
                                               codingPath: self.codingPath + [key])
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
        return XPCDecoderImpl(value: try value(forKey: key), codingPath: self.codingPath + [key])
    }
}

// MARK: functions that do the heavy lifting of actually decoding

/// Convenience extension to improve quality of error descriptions
fileprivate extension xpc_type_t {
    var description: String {
        switch self {
            case XPC_TYPE_ARRAY:
                return "array"
            case XPC_TYPE_DICTIONARY:
                return "dictionary"
            case XPC_TYPE_BOOL:
                return "bool"
            case XPC_TYPE_DATA:
                return "data"
            case XPC_TYPE_DATE:
                return "date"
            case XPC_TYPE_DOUBLE:
                return "double"
            case XPC_TYPE_INT64:
                return "int64"
            case XPC_TYPE_STRING:
                return "string"
            case XPC_TYPE_UINT64:
                return "unit64"
            case XPC_TYPE_UUID:
                return "uuid"
            case XPC_TYPE_ACTIVITY:
                return "activity"
            case XPC_TYPE_ENDPOINT:
                return "endpoint"
            case XPC_TYPE_ERROR:
                return "error"
            case XPC_TYPE_FD:
                return "file descriptor"
            case XPC_TYPE_SHMEM:
                return "shared memory"
            case XPC_TYPE_CONNECTION:
                return "connection"
            case XPC_TYPE_NULL:
                return "null"
            default:
                return "unknown"
        }
    }
}

private func baseDecode<T>(value: xpc_object_t,
                           xpcType: xpc_type_t,
                           transform: (xpc_object_t) throws -> T,
                           codingPath: [CodingKey]) throws -> T {
    if xpc_get_type(value) == xpcType {
        return try transform(value)
    } else {
        let debugDescription = "Actual: \(xpc_get_type(value).description), expected: \(String(describing: T.self))"
        let context = DecodingError.Context(codingPath: codingPath,
                                            debugDescription: debugDescription,
                                            underlyingError: nil)
        throw DecodingError.typeMismatch(T.self, context)
    }
}

private func intTransform<T: FixedWidthInteger & SignedInteger>(_ type: T.Type,
                                                                codingPath: [CodingKey]) -> (xpc_object_t) throws -> T {
    return { (object: xpc_object_t) in
        let value = xpc_int64_get_value(object)
        if value >= T.min && value <= T.max {
            return T(value)
        } else {
            let description = "\(value) out of range for \(String(describing: T.self)). Min: \(T.min), max: \(T.max)."
            let context = DecodingError.Context(codingPath: codingPath,
                                                debugDescription: description,
                                                underlyingError: nil)
            throw DecodingError.typeMismatch(T.self, context)
        }
    }
}

private func uintTransform<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type,
                                                                   codingPath: [CodingKey]) -> (xpc_object_t) throws -> T {
    return { (object: xpc_object_t) in
        let value = xpc_uint64_get_value(object)
        if value <= T.max {
            return T(value)
        } else {
            let description = "\(value) out of range for \(String(describing: T.self)). Max: \(T.max)."
            let context = DecodingError.Context(codingPath: codingPath,
                                                debugDescription: description,
                                                underlyingError: nil)
            throw DecodingError.typeMismatch(T.self, context)
        }
    }
}

private func stringTransform(codingPath: [CodingKey]) -> ((xpc_object_t) throws -> String) {
    return { (object: xpc_object_t) in
        if let stringPointer = xpc_string_get_string_ptr(object) {
            return String(cString: stringPointer)
        } else {
            let context = DecodingError.Context(codingPath: codingPath,
                                                debugDescription: "Unable to decode string",
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
    }
}

private let floatTransform = { (object: xpc_object_t) -> Float in
    // Double.signalingNaN is not converted to Float.signalingNaN when calling Float(...) with a Double so this needs
    // to be done manually
    let doubleValue = xpc_double_get_value(object)
    let floatValue = doubleValue.isSignalingNaN ? Float.signalingNaN : Float(doubleValue)
    
    return floatValue
}
