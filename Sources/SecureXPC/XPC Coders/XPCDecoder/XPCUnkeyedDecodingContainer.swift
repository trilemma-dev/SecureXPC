//
//  XPCUnkeyedDecodingContainer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

enum XPCUnkeyedDecodingContainer {
    /// Returns a container to perform the decoding.
    ///
    /// Depending on how the container was encoded it may either return one that operates on an XPC array or an XPC data instance.
    static func containerFor(value: xpc_object_t,
                             codingPath: [CodingKey],
                             userInfo: [CodingUserInfoKey : Any]) throws -> UnkeyedDecodingContainer {
        let type = xpc_get_type(value)
        if type == XPC_TYPE_ARRAY {
            return try XPCArrayBackedUnkeyedDecodingContainer(value: value,
                                                              codingPath: codingPath,
                                                              userInfo: userInfo)
        } else if type == XPC_TYPE_DATA {
            return try XPCDataBackedUnkeyedDecodingContainer(value: value, codingPath: codingPath)
        } else {
            let context = DecodingError.Context(codingPath: codingPath,
                                                debugDescription: "Expected array or data, was \(type.description)",
                                                underlyingError: nil)
            throw DecodingError.typeMismatch(XPCUnkeyedDecodingContainer.self, context)
        }
    }
}

/// Decodes from an XPC array.
private class XPCArrayBackedUnkeyedDecodingContainer: UnkeyedDecodingContainer {
	private let array: [xpc_object_t]
	var currentIndex: Int
	var codingPath = [CodingKey]()
    let userInfo: [CodingUserInfoKey : Any]

    init(value: xpc_object_t, codingPath: [CodingKey], userInfo: [CodingUserInfoKey : Any]) throws {
		if xpc_get_type(value) == XPC_TYPE_ARRAY {
			var array = [xpc_object_t]()
			let count = xpc_array_get_count(value)
			for index in 0..<count {
				array.append(xpc_array_get_value(value, index))
			}
			self.array = array
			self.currentIndex = 0
			self.codingPath = codingPath
            self.userInfo = userInfo
        } else {
			let context = DecodingError.Context(codingPath: codingPath,
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
		let decodedElement = try T(from: XPCDecoderImpl(value: try nextElement(type),
                                                        codingPath: self.codingPath,
                                                        userInfo: self.userInfo))
		currentIndex += 1

		return decodedElement
	}

	func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
		let value = try nextElement(UnkeyedDecodingContainer.self)
		let container = KeyedDecodingContainer<NestedKey>(try XPCKeyedDecodingContainer(value: value,
																						codingPath: self.codingPath,
                                                                                        userInfo: self.userInfo))
		currentIndex += 1

		return container
	}

	func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let container = try XPCUnkeyedDecodingContainer.containerFor(
            value: try nextElement(UnkeyedDecodingContainer.self),
            codingPath: self.codingPath,
            userInfo: self.userInfo)
		currentIndex += 1

		return container
	}

	func superDecoder() throws -> Decoder {
		let decoder = XPCDecoderImpl(value: try nextElement(Decoder.self),
                                     codingPath: self.codingPath,
                                     userInfo: self.userInfo)
		currentIndex += 1

		return decoder
	}
}

/// Decodes from an XPC data instance. As such, only certain value types are expected to be encoded and therefore supported when decoding.
private class XPCDataBackedUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    /// Contains the unkeyed elements to decode
    private let data: Data
    
    /// Offset into data
    private var currentOffset = 0
    
    /// The count is never known by this container
    let count: Int? = nil
    
    let codingPath: [CodingKey]
    var currentIndex = 0
    
    var isAtEnd: Bool {
        currentOffset >= data.count
    }
    
    init(value: xpc_object_t, codingPath: [CodingKey]) throws {
        self.codingPath = codingPath
        
        guard xpc_get_type(value) == XPC_TYPE_DATA else {
            let context = DecodingError.Context(codingPath:codingPath,
                                                debugDescription: "Not an data-backed array",
                                                underlyingError: nil)
            throw DecodingError.typeMismatch(XPCUnkeyedDecodingContainer.self, context)
        }
        
        
        let dataLength = xpc_data_get_length(value)
        if dataLength > 0 {
            guard let dataPointer = xpc_data_get_bytes_ptr(value) else {
                let context = DecodingError.Context(codingPath: codingPath,
                                                    debugDescription: "Array, encoded as data, could not be read",
                                                    underlyingError: nil)
                throw DecodingError.dataCorrupted(context)
            }
            self.data = Data(bytes: dataPointer, count: dataLength)
        } else {
            self.data = Data()
        }
    }
    
    /// Reads a portion of data as the specified type or throws an error if that's not supported
    ///
    /// Updates `currentOffset`, `currentIndex`, and `isAtEnd`.
    ///
    /// - Parameters:
    ///   - asType: The type to read the data as.
    /// - Returns: The `data` as an instance of `asType`.
    private func nextElement<T>(asType type: T.Type) throws -> T {
        // No more elements
        if isAtEnd {
            let context = DecodingError.Context(codingPath: codingPath,
                                                debugDescription: "Already at end, no remaining elements to decode",
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
        
        // Reading this element would put us past the end, which means something has gone wrong with the decoding
        if currentOffset + MemoryLayout<T>.size > data.count {
            let context = DecodingError.Context(codingPath: codingPath,
                                                debugDescription: "Decoding \(type) would read past end of container",
                                                underlyingError: nil)
            throw DecodingError.typeMismatch(type, context)
        }
        
        // Can't decode this type
        if !XPCUnkeyedEncodingContainer.supportedDataTypes.contains(where: { $0 == type }) {
            let context = DecodingError.Context(codingPath: codingPath,
                                                debugDescription: "Container can't decode \(type)",
                                                underlyingError: nil)
            throw DecodingError.typeMismatch(type, context)
        }
        
        // Decode the next element
        let result: T = data.withUnsafeBytes { pointer in
            // Directly loading using pointer.load(...) will not work in cases with mixed length types; it would
            // result in misaligned raw pointer access (which Swift disallows and additionally ARM CPUs do not support)
            // See https://forums.swift.org/t/accessing-a-misaligned-raw-pointer-safely/22743/2
            
            // Create a default value of the correct type (and therefore length) so that we can pass it to memcpy
            var value = Data(count: MemoryLayout<T>.size).withUnsafeBytes { pointer in
                pointer.load(as: type)
            }
            
            // Populate the value with memcpy
            memcpy(&value, pointer.baseAddress! + currentOffset, MemoryLayout<T>.size)
            
            return value
        }
        
        // Update offset related variables
        currentOffset += MemoryLayout<T>.size
        currentIndex += 1
        
        return result
    }
    
    // This container can't decode nil values
    func decodeNil() throws -> Bool {
        return false
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        return try nextElement(asType: KeyedDecodingContainer<NestedKey>.self)
    }
    
    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        return try nextElement(asType: UnkeyedDecodingContainer.self)
    }
    
    func superDecoder() throws -> Decoder {
        return try nextElement(asType: Decoder.self)
    }
    
    func decode(_ type: String.Type) throws -> String {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: Int8.Type) throws -> Int8 {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: Int16.Type) throws -> Int16 {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: Int32.Type) throws -> Int32 {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: Int64.Type) throws -> Int64 {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: UInt8.Type) throws -> UInt8 {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: UInt16.Type) throws -> UInt16 {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: UInt32.Type) throws -> UInt32 {
        return try nextElement(asType: type)
    }
    
    func decode(_ type: UInt64.Type) throws -> UInt64 {
        return try nextElement(asType: type)
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        return try nextElement(asType: type)
    }
}
