//
//  Dictinary encoding tests.swift
//
//
//  Created by Alexander Momchilov on 2021-11-03.
//

import XCTest
@testable import SecureXPC

final class XPCEncoder_DictionaryEncodingTests: XCTestCase {
	// MARK: Signed Integers
	
	func testEncodes_dictOf_SignedIntegers_asDictOf_XPCInts() throws {
		let dictOfInt:   [String: Int  ] = ["int"  : 123]
		let dictOfInt8:  [String: Int8 ] = ["int8" : 123]
		let dictOfInt16: [String: Int16] = ["int16": 123]
		let dictOfInt32: [String: Int32] = ["int32": 123]
		let dictOfInt64: [String: Int64] = ["int64": 123]
		
		try assert(  dictOfInt, encodesEqualTo: createXPCDict(from:   dictOfInt, using: { xpc_int64_create(Int64($0)) }))
		try assert( dictOfInt8, encodesEqualTo: createXPCDict(from:  dictOfInt8, using: { xpc_int64_create(Int64($0)) }))
		try assert(dictOfInt16, encodesEqualTo: createXPCDict(from: dictOfInt16, using: { xpc_int64_create(Int64($0)) }))
		try assert(dictOfInt32, encodesEqualTo: createXPCDict(from: dictOfInt32, using: { xpc_int64_create(Int64($0)) }))
		try assert(dictOfInt64, encodesEqualTo: createXPCDict(from: dictOfInt64, using: { xpc_int64_create(Int64($0)) }))
	}
	
	func testEncodes_dictOf_UnsignedIntegers_asDictOf_XPCUInts() throws {
		let dictOfUInt:   [String: UInt  ] = ["uint"  : 123]
		let dictOfUInt8:  [String: UInt8 ] = ["uint8" : 123]
		let dictOfUInt16: [String: UInt16] = ["uint16": 123]
		let dictOfUInt32: [String: UInt32] = ["uint32": 123]
		let dictOfUInt64: [String: UInt64] = ["uint64": 123]
		
		try assert(  dictOfUInt, encodesEqualTo: createXPCDict(from:   dictOfUInt, using: { xpc_uint64_create(UInt64($0)) }))
		try assert( dictOfUInt8, encodesEqualTo: createXPCDict(from:  dictOfUInt8, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(dictOfUInt16, encodesEqualTo: createXPCDict(from: dictOfUInt16, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(dictOfUInt32, encodesEqualTo: createXPCDict(from: dictOfUInt32, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(dictOfUInt64, encodesEqualTo: createXPCDict(from: dictOfUInt64, using: { xpc_uint64_create(UInt64($0)) }))
	}
	
	// MARK: Floating point numbers
	
	func testEncodes_dictOf_Floats_asDictOf_XPCDoubles() throws {
		let dictOfFloats: [String: Float] = [
			"-infinity": -.infinity,
			"-greatestFiniteMagnitude": -.greatestFiniteMagnitude,
			"-123": -123,
			"-leastNormalMagnitude": -.leastNormalMagnitude,
			"-leastNonzeroMagnitude": -.leastNonzeroMagnitude,
			"-0.0": -0.0,
			"0.0": 0.0,
			"leastNonzeroMagnitude": -.leastNonzeroMagnitude,
			"leastNormalMagnitude": -.leastNormalMagnitude,
			"123": 123,
			"greatestFiniteMagnitude": .greatestFiniteMagnitude,
			"infinity": .infinity,
		]

		try assert(dictOfFloats, encodesEqualTo: createXPCDict(from: dictOfFloats, using: { xpc_double_create(Double($0)) }))

		// These don't have regular equality, so we'll check them seperately.
		let nans = try encode(["nan": Float.nan, "signalingNaN": Float.signalingNaN])
		XCTAssertEqual(xpc_dictionary_get_count(nans), 2)
		XCTAssert(xpc_dictionary_get_double(nans, "nan").isNaN)
		XCTAssert(xpc_dictionary_get_double(nans, "signalingNaN").isNaN)
	}
	
	func testEncodes_dictOf_Doubles_asDictOf_XPCDoubles() throws {
		let dictOfDoubles: [String: Double] = [
			"-infinity": -.infinity,
			"-greatestFiniteMagnitude": -.greatestFiniteMagnitude,
			"-123": -123,
			"-leastNormalMagnitude": -.leastNormalMagnitude,
			"-leastNonzeroMagnitude": -.leastNonzeroMagnitude,
			"-0.0": -0.0,
			"0.0": 0.0,
			"leastNonzeroMagnitude": -.leastNonzeroMagnitude,
			"leastNormalMagnitude": -.leastNormalMagnitude,
			"123": 123,
			"greatestFiniteMagnitude": .greatestFiniteMagnitude,
			"infinity": .infinity,
		]

		try assert(dictOfDoubles, encodesEqualTo: createXPCDict(from: dictOfDoubles, using: { xpc_double_create(Double($0)) }))

		// These don't have regular equality, so we'll check them seperately.
		let nans = try encode(["nan": Double.nan, "signalingNaN": Double.signalingNaN])
		XCTAssertEqual(xpc_dictionary_get_count(nans), 2)
		XCTAssert(xpc_dictionary_get_double(nans, "nan").isNaN)
		XCTAssert(xpc_dictionary_get_double(nans, "signalingNaN").isNaN)
	}
	
	// MARK: Misc. types
	
	func testEncodes_dictOf_Bools_asDictOf_XPCBools() throws {
		let bools: [String: Bool?] = ["false": false, "true": true, "nil": nil]
		try assert(bools, encodesEqualTo: createXPCDict(from: bools, using: xpc_bool_create))
	}
	
	func testEncodes_dictOf_Strings_asDictOf_XPCStrings() throws {
		let strings: [String: String] = ["empty": "", "string": "Hello, world!"]
		try assert(strings, encodesEqualTo: createXPCDict(from: strings, using: { str in
			str.withCString(xpc_string_create)
		}))
	}
	
	func testEncodes_dictsOf_Nils() throws {
		// Signed integers
		let dictOfInt:   [String: Optional<Int  >] = ["int"  : 123, "nil": nil]
		let dictOfInt8:  [String: Optional<Int8 >] = ["int8" : 123, "nil": nil]
		let dictOfInt16: [String: Optional<Int16>] = ["int16": 123, "nil": nil]
		let dictOfInt32: [String: Optional<Int32>] = ["int32": 123, "nil": nil]
		let dictOfInt64: [String: Optional<Int64>] = ["int64": 123, "nil": nil]
		
		try assert(  dictOfInt, encodesEqualTo: createXPCDict(from:   dictOfInt, using: { xpc_int64_create(Int64($0)) }))
		try assert( dictOfInt8, encodesEqualTo: createXPCDict(from:  dictOfInt8, using: { xpc_int64_create(Int64($0)) }))
		try assert(dictOfInt16, encodesEqualTo: createXPCDict(from: dictOfInt16, using: { xpc_int64_create(Int64($0)) }))
		try assert(dictOfInt32, encodesEqualTo: createXPCDict(from: dictOfInt32, using: { xpc_int64_create(Int64($0)) }))
		try assert(dictOfInt64, encodesEqualTo: createXPCDict(from: dictOfInt64, using: { xpc_int64_create(Int64($0)) }))
		
		let dictOfUInt:   [String: Optional<UInt  >] = ["uint"  : 123, "nil": nil]
		let dictOfUInt8:  [String: Optional<UInt8 >] = ["uint8" : 123, "nil": nil]
		let dictOfUInt16: [String: Optional<UInt16>] = ["uint16": 123, "nil": nil]
		let dictOfUInt32: [String: Optional<UInt32>] = ["uint32": 123, "nil": nil]
		let dictOfUInt64: [String: Optional<UInt64>] = ["uint64": 123, "nil": nil]
		
		try assert(  dictOfUInt, encodesEqualTo: createXPCDict(from:   dictOfUInt, using: { xpc_uint64_create(UInt64($0)) }))
		try assert( dictOfUInt8, encodesEqualTo: createXPCDict(from:  dictOfUInt8, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(dictOfUInt16, encodesEqualTo: createXPCDict(from: dictOfUInt16, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(dictOfUInt32, encodesEqualTo: createXPCDict(from: dictOfUInt32, using: { xpc_uint64_create(UInt64($0)) }))
		try assert(dictOfUInt64, encodesEqualTo: createXPCDict(from: dictOfUInt64, using: { xpc_uint64_create(UInt64($0)) }))

		// Floating point numbers
		let floats: [String: Float?] = ["float": 123, "nil": nil]
		try assert(floats, encodesEqualTo: createXPCDict(from: floats, using: { xpc_double_create(Double($0)) }))
		let doubles: [String: Double?] = ["double": 123, "nil": nil]
		try assert(doubles, encodesEqualTo: createXPCDict(from: doubles, using: { xpc_double_create($0) }))

		// Misc. types
		
		let bools: [String: Bool?] = ["false": false, "true": true, "nil": nil]
		try assert(bools, encodesEqualTo: createXPCDict(from: bools, using: xpc_bool_create))
		
		let strings: [String: String?] = ["empty": "", "string": "Hello, world!", "nil": nil]
		try assert(strings, encodesEqualTo: createXPCDict(from: strings, using: { str in
			str.withCString(xpc_string_create)
		}))
	}
	
	// MARK: Dictionaries of aggregates
	
	func testEncode_dictOf_Arrays() throws {
		// There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
		let dictOfArrays: [String: [Int64]] = [
			"a1": [1, 2, 3],
			"a2": [4, 5, 6],
		]
		
		let expectedXPCDict = createXPCDict(from: dictOfArrays, using: { array in
			createXPCArray(from: array, using: xpc_int64_create)
		})
		
		try assert(dictOfArrays, encodesEqualTo: expectedXPCDict)
	}
	
	func testEncode_dictOf_Dicts() throws {
		// There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
		let dictOfDicts: [String: [String: Int64]] = [
			"d1": ["a": 1, "b": 2, "c": 3],
			"d2": ["d": 4, "e": 5, "f": 6],
		]
		
		let expectedXPCDict = createXPCDict(from: dictOfDicts, using: { subDict in
			createXPCDict(from: subDict, using: xpc_int64_create)
		})
		
		try assert(dictOfDicts, encodesEqualTo: expectedXPCDict)
	}
}

