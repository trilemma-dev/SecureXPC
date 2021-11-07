//
//  Dictinary encoding tests.swift
//
//
//  Created by Alexander Momchilov on 2021-11-03.
//

import XCTest
@testable import SecureXPC

final class XPCDecoder_DictionaryEncodingTests: XCTestCase {
	// MARK: Signed Integers
	
	func testDecodes_dictOf_SignedIntegers_asDictOf_XPCInts() throws {
		let dictOfInt:   [String: Int  ] = ["int"  : 123]
		let dictOfInt8:  [String: Int8 ] = ["int8" : 123]
		let dictOfInt16: [String: Int16] = ["int16": 123]
		let dictOfInt32: [String: Int32] = ["int32": 123]
		let dictOfInt64: [String: Int64] = ["int64": 123]
		
		try assert(createXPCDict(from:   dictOfInt, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo:   dictOfInt)
		try assert(createXPCDict(from:  dictOfInt8, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo:  dictOfInt8)
		try assert(createXPCDict(from: dictOfInt16, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: dictOfInt16)
		try assert(createXPCDict(from: dictOfInt32, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: dictOfInt32)
		try assert(createXPCDict(from: dictOfInt64, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: dictOfInt64)
	}
	
	func testDecodes_dictOf_UnsignedIntegers_asDictOf_XPCUInts() throws {
		let dictOfUInt:   [String: UInt  ] = ["uint"  : 123]
		let dictOfUInt8:  [String: UInt8 ] = ["uint8" : 123]
		let dictOfUInt16: [String: UInt16] = ["uint16": 123]
		let dictOfUInt32: [String: UInt32] = ["uint32": 123]
		let dictOfUInt64: [String: UInt64] = ["uint64": 123]
		
		try assert(createXPCDict(from:   dictOfUInt, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo:   dictOfUInt)
		try assert(createXPCDict(from:  dictOfUInt8, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo:  dictOfUInt8)
		try assert(createXPCDict(from: dictOfUInt16, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: dictOfUInt16)
		try assert(createXPCDict(from: dictOfUInt32, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: dictOfUInt32)
		try assert(createXPCDict(from: dictOfUInt64, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: dictOfUInt64)
	}
	
	// MARK: Floating point numbers
	
	func testDecodes_dictOf_Floats_asDictOf_XPCDoubles() throws {
		func floatToXPCDouble(_ input: Float) -> xpc_object_t {
			xpc_double_create(Double(input))
		}

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

		try assert(createXPCDict(from: dictOfFloats, using: floatToXPCDouble), decodesEqualTo: dictOfFloats)

		// These don't have regular equality, so we'll check them seperately.
		let nans: [String: Float] = try decode(createXPCDict(from: [
			"nan": Float.nan,
			"signalingNaN": Float.signalingNaN
		], using: floatToXPCDouble))
		XCTAssertEqual(nans.count, 2)
		XCTAssert(nans["nan"]!.isNaN)
		XCTAssert(nans["signalingNaN"]!.isNaN)
	}

	func testDecodes_dictOf_Doubles_asDictOf_XPCDoubles() throws {
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

		try assert(createXPCDict(from: dictOfDoubles, using: xpc_double_create), decodesEqualTo: dictOfDoubles)

		// These don't have regular equality, so we'll check them seperately.
		let nans: [String: Double] = try decode(createXPCDict(from: [
			"nan": Double.nan,
			"signalingNaN": Double.signalingNaN
		], using: xpc_double_create))
		XCTAssertEqual(nans.count, 2)
		XCTAssert(nans["nan"]!.isNaN)
		XCTAssert(nans["signalingNaN"]!.isNaN)
	}

	// MARK: Misc. types

	func testDecodes_dictOf_Bools_asDictOf_XPCBools() throws {
		let bools: [String: Bool] = ["false": false, "true": true]
		try assert(createXPCDict(from: bools, using: xpc_bool_create), decodesEqualTo: bools)
	}

	func testDecodes_dictOf_Strings_asDictOf_XPCStrings() throws {
		let strings: [String: String] = ["empty": "", "string": "Hello, world!"]
		let xpcStrings = createXPCDict(from: strings, using: { str in
			str.withCString(xpc_string_create)
		})

		try assert(xpcStrings, decodesEqualTo: strings)
	}

	func testDecodes_dictsOf_Nils() throws {
		// Signed integers
		let dictOfInt:   [String: Optional<Int  >] = ["int"  : 123, "nil": nil]
		let dictOfInt8:  [String: Optional<Int8 >] = ["int8" : 123, "nil": nil]
		let dictOfInt16: [String: Optional<Int16>] = ["int16": 123, "nil": nil]
		let dictOfInt32: [String: Optional<Int32>] = ["int32": 123, "nil": nil]
		let dictOfInt64: [String: Optional<Int64>] = ["int64": 123, "nil": nil]

		try assert(createXPCDict(from:   dictOfInt, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo:   dictOfInt)
		try assert(createXPCDict(from:  dictOfInt8, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo:  dictOfInt8)
		try assert(createXPCDict(from: dictOfInt16, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: dictOfInt16)
		try assert(createXPCDict(from: dictOfInt32, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: dictOfInt32)
		try assert(createXPCDict(from: dictOfInt64, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: dictOfInt64)

		let dictOfUInt:   [String: Optional<UInt  >] = ["uint"  : 123, "nil": nil]
		let dictOfUInt8:  [String: Optional<UInt8 >] = ["uint8" : 123, "nil": nil]
		let dictOfUInt16: [String: Optional<UInt16>] = ["uint16": 123, "nil": nil]
		let dictOfUInt32: [String: Optional<UInt32>] = ["uint32": 123, "nil": nil]
		let dictOfUInt64: [String: Optional<UInt64>] = ["uint64": 123, "nil": nil]

		try assert(createXPCDict(from:   dictOfUInt, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo:   dictOfUInt)
		try assert(createXPCDict(from:  dictOfUInt8, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo:  dictOfUInt8)
		try assert(createXPCDict(from: dictOfUInt16, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: dictOfUInt16)
		try assert(createXPCDict(from: dictOfUInt32, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: dictOfUInt32)
		try assert(createXPCDict(from: dictOfUInt64, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: dictOfUInt64)

		// Floating point numbers
		let floats: [String: Float?] = ["float": 123, "nil": nil]
		try assert(createXPCDict(from: floats, using: { xpc_double_create(Double($0)) }), decodesEqualTo: floats)
		let doubles: [String: Double?] = ["double": 123, "nil": nil]
		try assert(createXPCDict(from: doubles, using: { xpc_double_create($0) }), decodesEqualTo: doubles)

		// Misc. types

		let bools: [String: Bool?] = ["false": false, "true": true, "nil": nil]
		try assert(createXPCDict(from: bools, using: xpc_bool_create), decodesEqualTo: bools)

		let strings: [String: String?] = ["empty": "", "string": "Hello, world!", "nil": nil]
		try assert(createXPCDict(from: strings, using: { str in
			str.withCString(xpc_string_create)
		}), decodesEqualTo: strings)
	}

	// MARK: Dictionaries of aggregates

	func testDecode_dictOf_Arrays() throws {
		// There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
		let expectedResultDictOfArrays: [String: [Int64]] = [
			"a1": [1, 2, 3],
			"a2": [4, 5, 6],
		]

		let inputXPCDict = createXPCDict(from: expectedResultDictOfArrays, using: { array in
			createXPCArray(from: array, using: xpc_int64_create)
		})

		try assert(inputXPCDict, decodesEqualTo: expectedResultDictOfArrays)
	}

	func testDecode_dictOf_Dicts() throws {
		// There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
		let expectedResultDictOfDicts: [String: [String: Int64]] = [
			"d1": ["a": 1, "b": 2, "c": 3],
			"d2": ["d": 4, "e": 5, "f": 6],
		]

		let inputXPCDict = createXPCDict(from: expectedResultDictOfDicts, using: { subDict in
			createXPCDict(from: subDict, using: xpc_int64_create)
		})

		try assert(inputXPCDict, decodesEqualTo: expectedResultDictOfDicts)
	}
}

