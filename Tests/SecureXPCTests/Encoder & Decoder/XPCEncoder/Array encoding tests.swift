import XCTest
@testable import SecureXPC

final class XPCEncoder_ArrayEncodingTests: XCTestCase {
	// MARK: Integers
	
	func testEncodes_arrayOf_SignedIntegers_asXPCData() throws {
		let   ints: [Int  ] = [.min, -123, 0, 123, .max]
		let  int8s: [Int8 ] = [.min, -123, 0, 123, .max]
		let int16s: [Int16] = [.min, -123, 0, 123, .max]
		let int32s: [Int32] = [.min, -123, 0, 123, .max]
		let int64s: [Int64] = [.min, -123, 0, 123, .max]
		
		try assert(  ints, encodesEqualTo: createXPCData(fromArray:   ints))
		try assert( int8s, encodesEqualTo: createXPCData(fromArray:  int8s))
		try assert(int16s, encodesEqualTo: createXPCData(fromArray: int16s))
		try assert(int32s, encodesEqualTo: createXPCData(fromArray: int32s))
		try assert(int64s, encodesEqualTo: createXPCData(fromArray: int64s))
	}
	
	func testEncodes_arrayOf_UnsignedIntegers_asXPCData() throws {
		let   uints: [UInt  ] = [.min, 0, 123, .max]
		let  uint8s: [UInt8 ] = [.min, 0, 123, .max]
		let uint16s: [UInt16] = [.min, 0, 123, .max]
		let uint32s: [UInt32] = [.min, 0, 123, .max]
		let uint64s: [UInt64] = [.min, 0, 123, .max]
		
        try assert(  uints, encodesEqualTo: createXPCData(fromArray:   uints))
        try assert( uint8s, encodesEqualTo: createXPCData(fromArray:  uint8s))
        try assert(uint16s, encodesEqualTo: createXPCData(fromArray: uint16s))
        try assert(uint32s, encodesEqualTo: createXPCData(fromArray: uint32s))
        try assert(uint64s, encodesEqualTo: createXPCData(fromArray: uint64s))
	}
	
	// MARK: Floating point numbers
	
	func testEncodes_arrayOf_Floats_asXPCData() throws {
		let floats: [Float] = [
			-Float.infinity,
			-Float.greatestFiniteMagnitude,
			-123,
			-Float.leastNormalMagnitude,
			-Float.leastNonzeroMagnitude,
			-0.0,
			 0.0,
			 Float.leastNonzeroMagnitude,
			 Float.leastNormalMagnitude,
			 123,
			 Float.greatestFiniteMagnitude,
			 Float.infinity
		]
		
		try assert(floats, encodesEqualTo: createXPCData(fromArray: floats))
		
		// These don't have regular equality, so we'll check them seperately.
        let nans = [Float.nan, Float.signalingNaN]
        let encodedNans = try encode(nans)
        
        let floatSize = MemoryLayout<Float>.size
        let encodedNansLength = xpc_data_get_length(encodedNans)
        XCTAssertEqual(encodedNansLength, nans.count * floatSize)
        
        let encodedNansData = Data(bytes: xpc_data_get_bytes_ptr(encodedNans)!,
                                    count: encodedNansLength)
        let decodedNan = encodedNansData[0..<floatSize].withUnsafeBytes { pointer in
            pointer.load(as: Float.self)
        }
        XCTAssert(decodedNan.isNaN)
        
        let decodedSignalingNan = encodedNansData[floatSize..<2 * floatSize].withUnsafeBytes { pointer in
            pointer.load(as: Float.self)
        }
        XCTAssert(decodedSignalingNan.isNaN)
        XCTAssert(decodedSignalingNan.isSignalingNaN)
	}
	
	func testEncodes_arrayOf_Doubles_asXPCData() throws {
		let doubles: [Double] = [
			-Double.infinity,
			-Double.greatestFiniteMagnitude,
			-Double.leastNormalMagnitude,
			-Double.leastNonzeroMagnitude,
			-123,
			-0.0,
			 0.0,
			 123,
			 Double.leastNonzeroMagnitude,
			 Double.leastNormalMagnitude,
			 Double.greatestFiniteMagnitude,
			 Double.infinity
		]
		
		try assert(doubles, encodesEqualTo: createXPCData(fromArray: doubles))
		
        // These don't have regular equality, so we'll check them seperately.
        let nans = [Double.nan, Double.signalingNaN]
        let encodedNans = try encode(nans)
        
        let doubleSize = MemoryLayout<Double>.size
        let encodedNansLength = xpc_data_get_length(encodedNans)
        XCTAssertEqual(encodedNansLength, nans.count * doubleSize)
        
        let encodedNansData = Data(bytes: xpc_data_get_bytes_ptr(encodedNans)!,
                                    count: encodedNansLength)
        let decodedNan = encodedNansData[0..<doubleSize].withUnsafeBytes { pointer in
            pointer.load(as: Double.self)
        }
        XCTAssert(decodedNan.isNaN)
        
        let decodedSignalingNan = encodedNansData[doubleSize..<2 * doubleSize].withUnsafeBytes { pointer in
            pointer.load(as: Double.self)
        }
        XCTAssert(decodedSignalingNan.isNaN)
        XCTAssert(decodedSignalingNan.isSignalingNaN)
	}
	
	// MARK: Misc. types
	
	func testEncodes_arrayOf_Bools_asXPCData() throws {
		let bools = [false, true]
		try assert(bools, encodesEqualTo: createXPCData(fromArray: bools))
	}
	
	func testEncodes_arrayOf_Strings_asArrayOf_XPCStrings() throws {
		let strings = ["", "Hello, world!"]
		try assert(strings, encodesEqualTo: createXPCArray(from: strings, using: { str in
			str.withCString(xpc_string_create)
		}))
	}
	
	func testEncodes_arrayOf_nils() throws {
		// Signed integers
		let   ints: [Optional<Int  >] = [.min, -123, 0, 123, .max, nil]
		let  int8s: [Optional<Int8 >] = [.min, -123, 0, 123, .max, nil]
		let int16s: [Optional<Int16>] = [.min, -123, 0, 123, .max, nil]
		let int32s: [Optional<Int32>] = [.min, -123, 0, 123, .max, nil]
		let int64s: [Optional<Int64>] = [.min, -123, 0, 123, .max, nil]
		
		try assert(  ints, encodesEqualTo: createXPCArray(from:   ints, using: { xpc_int64_create(Int64($0)) }))
		try assert( int8s, encodesEqualTo: createXPCArray(from:  int8s, using: { xpc_int64_create(Int64($0)) }))
		try assert(int16s, encodesEqualTo: createXPCArray(from: int16s, using: { xpc_int64_create(Int64($0)) }))
		try assert(int32s, encodesEqualTo: createXPCArray(from: int32s, using: { xpc_int64_create(Int64($0)) }))
		try assert(int64s, encodesEqualTo: createXPCArray(from: int64s, using: { xpc_int64_create(Int64($0)) }))
		
		// Unsigned integers
		let   uints: [Optional<UInt  >] = [.min, 0, 123, .max, nil]
		let  uint8s: [Optional<UInt8 >] = [.min, 0, 123, .max, nil]
		let uint16s: [Optional<UInt16>] = [.min, 0, 123, .max, nil]
		let uint32s: [Optional<UInt32>] = [.min, 0, 123, .max, nil]
		let uint64s: [Optional<UInt64>] = [.min, 0, 123, .max, nil]
		
		try assert(  uints, encodesEqualTo: createXPCArray(from:   uints, using: { xpc_uint64_create(UInt64($0)) }))
		try assert( uint8s, encodesEqualTo: createXPCArray(from:  uint8s, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(uint16s, encodesEqualTo: createXPCArray(from: uint16s, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(uint32s, encodesEqualTo: createXPCArray(from: uint32s, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(uint64s, encodesEqualTo: createXPCArray(from: uint64s, using: { xpc_uint64_create(UInt64($0)) }))
		
		// Floating point numbers
		let floats: [Float?] = [-123, 0, 123, nil]
		try assert(floats, encodesEqualTo: createXPCArray(from: floats, using: { xpc_double_create(Double($0)) }))
		let doubles: [Double?] = [-123, 0, 123, nil]
		try assert(floats, encodesEqualTo: createXPCArray(from: doubles, using: { xpc_double_create($0) }))
		
		// Misc. types
		let bools: [Bool?] = [false, true, nil]
		try assert(bools, encodesEqualTo: createXPCArray(from: bools, using: { xpc_bool_create($0) }))
		
		let strings: [String?] = ["", "Hello, world!", nil]
		try assert(strings, encodesEqualTo: createXPCArray(from: strings, using: { str in
			str.withCString(xpc_string_create)
		}))
	}
	
	// MARK: Arrays of aggregates
	
	func testEncode_arrayOf_XPCData() throws {
		// There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
		let nestedArray: [[Int64]] = [[1, 2], [3, 4]]
		
		let expectedXPCArray = createXPCArray(from: nestedArray, using: { row in
			createXPCData(fromArray: row)
		})
		
		try assert(nestedArray, encodesEqualTo: expectedXPCArray)
	}
    
    func testEncode_arrayOf_Arrays() throws {
        // There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
        let nestedArray: [[String]] = [["1", "2"], ["3", "4"]]
        
        let expectedXPCArray = createXPCArray(from: nestedArray, using: { row in
            createXPCArray(from: row, using: { str in
                str.withCString(xpc_string_create)
            })
        })
        try assert(nestedArray, encodesEqualTo: expectedXPCArray)
    }
	
	func testEncodeArrayOfDictionaries() throws {
		// There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
		let arrayOfDicts: [[String: Int64]] = [
			["a": 1, "b": 2, "c": 3],
			["e": 4, "f": 5, "g": 6],
		]
		
		let expectedXPCArray = createXPCArray(from: arrayOfDicts, using: { subDict in
			createXPCDict(from: subDict, using: xpc_int64_create)
		})
		
		try assert(arrayOfDicts, encodesEqualTo: expectedXPCArray)
	}
}
