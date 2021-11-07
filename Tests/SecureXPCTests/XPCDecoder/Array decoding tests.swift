import XCTest
@testable import SecureXPC

final class XPCDecoder_ArrayDecodingTests: XCTestCase {
	// MARK: Signed Integers

	func testDecodes_arrayOf_SignedIntegers_asArrayOf_XPCInts() throws {
		let   ints: [Int  ] = [.min, -123, 0, 123, .max]
		let  int8s: [Int8 ] = [.min, -123, 0, 123, .max]
		let int16s: [Int16] = [.min, -123, 0, 123, .max]
		let int32s: [Int32] = [.min, -123, 0, 123, .max]
		let int64s: [Int64] = [.min, -123, 0, 123, .max]

		try assert(createXPCArray(from:   ints, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo:   ints)
		try assert(createXPCArray(from:  int8s, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo:  int8s)
		try assert(createXPCArray(from: int16s, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: int16s)
		try assert(createXPCArray(from: int32s, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: int32s)
		try assert(createXPCArray(from: int64s, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: int64s)
	}

	func testDecodes_arrayOf_UnsignedIntegers_asArrayOf_XPCUInts() throws {
		let   uints: [UInt  ] = [.min, 0, 123, .max]
		let  uint8s: [UInt8 ] = [.min, 0, 123, .max]
		let uint16s: [UInt16] = [.min, 0, 123, .max]
		let uint32s: [UInt32] = [.min, 0, 123, .max]
		let uint64s: [UInt64] = [.min, 0, 123, .max]

		try assert(createXPCArray(from:   uints, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo:   uints)
		try assert(createXPCArray(from:  uint8s, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo:  uint8s)
		try assert(createXPCArray(from: uint16s, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: uint16s)
		try assert(createXPCArray(from: uint32s, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: uint32s)
		try assert(createXPCArray(from: uint64s, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: uint64s)
	}

	// MARK: Floating point numbers

	func testDecodes_arrayOf_Floats_asArrayOf_XPCDoubles() throws {
		func floatToXPCDouble(_ input: Float) -> xpc_object_t {
			xpc_double_create(Double(input))
		}

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

		try assert(createXPCArray(from: floats, using: floatToXPCDouble), decodesEqualTo: floats)

		// These don't have regular equality, so we'll check them seperately.

		let nans: [Float] = try decode(createXPCArray(from: [.nan, .signalingNaN], using: floatToXPCDouble))
		XCTAssertEqual(nans.count, 2)
		XCTAssert(nans[0].isNaN)
		XCTAssert(nans[1].isNaN)
	}

	func testDecodes_arrayOf_Doubles_asArrayOf_XPCDoubles() throws {
		let doubles: [Double] = [
			-Double.infinity,
			-Double.greatestFiniteMagnitude,
			-123,
			-Double.leastNormalMagnitude,
			-Double.leastNonzeroMagnitude,
			-0.0,
			 0.0,
			 Double.leastNonzeroMagnitude,
			 Double.leastNormalMagnitude,
			 123,
			 Double.greatestFiniteMagnitude,
			 Double.infinity
		]

		try assert(createXPCArray(from: doubles, using: xpc_double_create), decodesEqualTo: doubles)

		// These don't have regular equality, so we'll check them seperately.
		let nans: [Float] = try decode(createXPCArray(from: [.nan, .signalingNaN], using: xpc_double_create))
		XCTAssertEqual(nans.count, 2)
		XCTAssert(nans[0].isNaN)
		XCTAssert(nans[1].isNaN)
	}

	// MARK: Misc. types

	func testDecodes_arrayOf_Bools_asArrayOf_XPCBools() throws {
		let bools = [false, true]
		try assert(createXPCArray(from: bools, using: xpc_bool_create), decodesEqualTo: bools)
	}

	func testDecodes_arrayOf_Strings_asArrayOf_XPCStrings() throws {
		let strings = ["", "Hello, world!"]
		let xpcStrings = createXPCArray(from: strings, using: { str in
			str.withCString(xpc_string_create)
		})

		try assert(xpcStrings, decodesEqualTo: strings)
	}

	func testDecodes_arrayOf_nils() throws {
		// Signed integers
		let   ints: [Optional<Int  >] = [.min, -123, 0, 123, .max, nil]
		let  int8s: [Optional<Int8 >] = [.min, -123, 0, 123, .max, nil]
		let int16s: [Optional<Int16>] = [.min, -123, 0, 123, .max, nil]
		let int32s: [Optional<Int32>] = [.min, -123, 0, 123, .max, nil]
		let int64s: [Optional<Int64>] = [.min, -123, 0, 123, .max, nil]

		try assert(createXPCArray(from:   ints, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo:   ints)
		try assert(createXPCArray(from:  int8s, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo:  int8s)
		try assert(createXPCArray(from: int16s, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: int16s)
		try assert(createXPCArray(from: int32s, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: int32s)
		try assert(createXPCArray(from: int64s, using: { xpc_int64_create(Int64($0)) }), decodesEqualTo: int64s)

		// Unsigned integers
		let   uints: [Optional<UInt  >] = [.min, 0, 123, .max, nil]
		let  uint8s: [Optional<UInt8 >] = [.min, 0, 123, .max, nil]
		let uint16s: [Optional<UInt16>] = [.min, 0, 123, .max, nil]
		let uint32s: [Optional<UInt32>] = [.min, 0, 123, .max, nil]
		let uint64s: [Optional<UInt64>] = [.min, 0, 123, .max, nil]

		try assert(createXPCArray(from:   uints, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo:   uints)
		try assert(createXPCArray(from:  uint8s, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo:  uint8s)
		try assert(createXPCArray(from: uint16s, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: uint16s)
		try assert(createXPCArray(from: uint32s, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: uint32s)
		try assert(createXPCArray(from: uint64s, using: { xpc_uint64_create(UInt64($0)) }), decodesEqualTo: uint64s)

		// Floating point numbers
		let floats: [Float?] = [-123, 0, 123, nil]
		try assert(createXPCArray(from: floats, using: { xpc_double_create(Double($0)) }), decodesEqualTo: floats)
		let doubles: [Double?] = [-123, 0, 123, nil]
		try assert(createXPCArray(from: doubles, using: { xpc_double_create(Double($0)) }), decodesEqualTo: floats)

		// Misc. types
		let bools: [Bool?] = [false, true, nil]
		try assert(createXPCArray(from: bools, using: xpc_bool_create), decodesEqualTo: bools)

		let strings: [String?] = ["", "Hello, world!", nil]
		try assert(createXPCArray(from: strings, using: { str in
			str.withCString(xpc_string_create)
		}), decodesEqualTo: strings)
	}

	// MARK: Arrays of aggregates

	func testDecode_arrayOf_Arrays() throws {
		// There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
		let expectedResultNestedArray: [[Int64]] = [[1, 2], [3, 4]]

		let inputXPCNestedArray = createXPCArray(from: expectedResultNestedArray, using: { row in
			createXPCArray(from: row, using: xpc_int64_create)
		})

		try assert(inputXPCNestedArray, decodesEqualTo: expectedResultNestedArray)
	}

	func testDecodeArrayOfDictionaries() throws {
		// There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
		let expectedResultArrayOfDicts: [[String: Int64]] = [
			["a": 1, "b": 2, "c": 3],
			["e": 4, "f": 5, "g": 6],
		]

		let inputXPCArrayOfDicts = createXPCArray(from: expectedResultArrayOfDicts, using: { subDict in
			createXPCDict(from: subDict, using: xpc_int64_create)
		})

		try assert(inputXPCArrayOfDicts, decodesEqualTo: expectedResultArrayOfDicts)
	}
}
