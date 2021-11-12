//
//  XPC Codable round trip tests.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-07.
//

import XCTest
@testable import SecureXPC

class SampleClass: Codable {
	// Properies need to be mutable, otherwise you get this warning:
	// "Immutable property will not be decoded because it is declared with an initial value which cannot be overwritten"

	var int  : Int   = -5
	var int8 : Int8  = -4
	var int16: Int16 = -3
	var int32: Int32 = -2
	var int64: Int64 = -1

	var uint  : UInt   = 0
	var uint8 : UInt8  = 1
	var uint16: UInt16 = 2
	var uint32: UInt32 = 3
	var uint64: UInt64 = 4

	var float: Float = 5
	var double: Double = 6

	var bool = false
	var string = "Hello, world!"

	var optionalString: String? = nil
}

class SampleSubClass: SampleClass {
	var sub_int  : Int   = -5
	var sub_int8 : Int8  = -4
	var sub_int16: Int16 = -3
	var sub_int32: Int32 = -2
	var sub_int64: Int64 = -1

	var sub_uint  : UInt   = 0
	var sub_uint8 : UInt8  = 1
	var sub_uint16: UInt16 = 2
	var sub_uint32: UInt32 = 3
	var sub_uint64: UInt64 = 4

	var sub_float: Float = 5
	var sub_double: Double = 6

	var sub_bool = false
	var sub_string = "Hello, world!"

	var sub_optionalString: String? = nil
}

final class XPCCodableRoundTripTests: XCTestCase {
	func testRoundTrip() throws {
		let original = SampleClass()
		let encoded: xpc_object_t = try encode(original)
		let decoded: SampleClass = try decode(encoded)
		assertEqual(decoded, original)
	}

	func testRoundTripWithInheritance() throws {
		let original = SampleSubClass()
		let encoded: xpc_object_t = try encode(original)
		let decoded: SampleSubClass = try decode(encoded)
		assertSubclassInstancesEqual(decoded, original)
	}

	private func assertEqual(
		_ actual: SampleClass,
		_ expected: SampleClass,
		file: StaticString = #file,
		line: UInt = #line
	) {
		// Swift doesn't auto-synthesize Equatable for classes. If we're going to write the boiler plate,
		// where each individual difference is reported, and many differences can be reported in a single test run.
		XCTAssertEqual(actual.int   , expected.int   )
		XCTAssertEqual(actual.int8  , expected.int8  )
		XCTAssertEqual(actual.int16 , expected.int16 )
		XCTAssertEqual(actual.int32 , expected.int32 )
		XCTAssertEqual(actual.int64 , expected.int64 )

		XCTAssertEqual(actual.uint  , expected.uint  )
		XCTAssertEqual(actual.uint8 , expected.uint8 )
		XCTAssertEqual(actual.uint16, expected.uint16)
		XCTAssertEqual(actual.uint32, expected.uint32)
		XCTAssertEqual(actual.uint64, expected.uint64)

		XCTAssertEqual(actual.float , expected.float )
		XCTAssertEqual(actual.double, expected.double)

		XCTAssertEqual(actual.bool  , expected.bool  )
		XCTAssertEqual(actual.string, expected.string)
		XCTAssertEqual(actual.optionalString, expected.optionalString)
	}

	private func assertSubclassInstancesEqual(
		_ actual: SampleSubClass,
		_ expected: SampleSubClass,
		file: StaticString = #file,
		line: UInt = #line
   ) {
	   XCTAssertEqual(actual.sub_int   , expected.sub_int   )
	   XCTAssertEqual(actual.sub_int8  , expected.sub_int8  )
	   XCTAssertEqual(actual.sub_int16 , expected.sub_int16 )
	   XCTAssertEqual(actual.sub_int32 , expected.sub_int32 )
	   XCTAssertEqual(actual.sub_int64 , expected.sub_int64 )

	   XCTAssertEqual(actual.sub_uint  , expected.sub_uint  )
	   XCTAssertEqual(actual.sub_uint8 , expected.sub_uint8 )
	   XCTAssertEqual(actual.sub_uint16, expected.sub_uint16)
	   XCTAssertEqual(actual.sub_uint32, expected.sub_uint32)
	   XCTAssertEqual(actual.sub_uint64, expected.sub_uint64)

	   XCTAssertEqual(actual.sub_float , expected.sub_float )
	   XCTAssertEqual(actual.sub_double, expected.sub_double)

	   XCTAssertEqual(actual.sub_bool  , expected.sub_bool  )
	   XCTAssertEqual(actual.sub_string, expected.sub_string)
	   XCTAssertEqual(actual.sub_optionalString, expected.sub_optionalString)

	   assertEqual(actual, expected, file: file, line: line)
   }
}
