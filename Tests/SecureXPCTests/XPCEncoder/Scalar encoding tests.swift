import XCTest
@testable import SecureXPC

final class XPCEncoder_ScalarEncodingTests: XCTestCase {
	// MARK: Signed Integers
	
	func testEncodes_Int_as_XPCInt64() throws {
		try assert(.min as Int, encodesEqualTo: xpc_int64_create(Int64(Int.min)))
		try assert(-123 as Int, encodesEqualTo: xpc_int64_create(          -123))
		try assert(   0 as Int, encodesEqualTo: xpc_int64_create(             0))
		try assert( 123 as Int, encodesEqualTo: xpc_int64_create(           123))
		try assert(.max as Int, encodesEqualTo: xpc_int64_create(Int64(Int.max)))
	}
	
	func testEncodes_Int8_as_XPCInt64() throws {
		try assert(.min as Int8, encodesEqualTo: xpc_int64_create(Int64(Int8.min)))
		try assert(-123 as Int8, encodesEqualTo: xpc_int64_create(           -123))
		try assert(   0 as Int8, encodesEqualTo: xpc_int64_create(              0))
		try assert( 123 as Int8, encodesEqualTo: xpc_int64_create(            123))
		try assert(.max as Int8, encodesEqualTo: xpc_int64_create(Int64(Int8.max)))
	}
	
	func testEncodes_Int16_as_XPCInt64() throws {
		try assert(.min as Int16, encodesEqualTo: xpc_int64_create(Int64(Int16.min)))
		try assert(-123 as Int16, encodesEqualTo: xpc_int64_create(            -123))
		try assert(   0 as Int16, encodesEqualTo: xpc_int64_create(               0))
		try assert( 123 as Int16, encodesEqualTo: xpc_int64_create(             123))
		try assert(.max as Int16, encodesEqualTo: xpc_int64_create(Int64(Int16.max)))
	}
	
	func testEncodes_Int32_as_XPCInt64() throws {
		try assert(.min as Int32, encodesEqualTo: xpc_int64_create(Int64(Int32.min)))
		try assert(-123 as Int32, encodesEqualTo: xpc_int64_create(            -123))
		try assert(   0 as Int32, encodesEqualTo: xpc_int64_create(               0))
		try assert( 123 as Int32, encodesEqualTo: xpc_int64_create(             123))
		try assert(.max as Int32, encodesEqualTo: xpc_int64_create(Int64(Int32.max)))
	}
	
	func testEncodes_Int64_as_XPCInt64() throws {
		try assert(.min as Int64, encodesEqualTo: xpc_int64_create(Int64(Int64.min)))
		try assert(-123 as Int64, encodesEqualTo: xpc_int64_create(            -123))
		try assert(   0 as Int64, encodesEqualTo: xpc_int64_create(               0))
		try assert( 123 as Int64, encodesEqualTo: xpc_int64_create(             123))
		try assert(.max as Int64, encodesEqualTo: xpc_int64_create(Int64(Int64.max)))
	}
	
	// MARK: Unsigned Integers
	
	func testEncodes_UInt_as_XPCUInt64() throws {
		try assert(.min as UInt, encodesEqualTo: xpc_uint64_create(UInt64(UInt.min)))
		try assert(   0 as UInt, encodesEqualTo: xpc_uint64_create(               0))
		try assert( 123 as UInt, encodesEqualTo: xpc_uint64_create(             123))
		try assert(.max as UInt, encodesEqualTo: xpc_uint64_create(UInt64(UInt.max)))
	}
	
	func testEncodes_UInt8_as_XPCUInt64() throws {
		try assert(.min as UInt8, encodesEqualTo: xpc_uint64_create(UInt64(UInt8.min)))
		try assert(   0 as UInt8, encodesEqualTo: xpc_uint64_create(                0))
		try assert( 123 as UInt8, encodesEqualTo: xpc_uint64_create(              123))
		try assert(.max as UInt8, encodesEqualTo: xpc_uint64_create(UInt64(UInt8.max)))
	}
	
	func testEncodes_UInt16_as_XPCUInt64() throws {
		try assert(.min as UInt16, encodesEqualTo: xpc_uint64_create(UInt64(UInt16.min)))
		try assert(   0 as UInt16, encodesEqualTo: xpc_uint64_create(                 0))
		try assert( 123 as UInt16, encodesEqualTo: xpc_uint64_create(               123))
		try assert(.max as UInt16, encodesEqualTo: xpc_uint64_create(UInt64(UInt16.max)))
	}
	
	func testEncodes_UInt32_as_XPCUInt64() throws {
		try assert(.min as UInt32, encodesEqualTo: xpc_uint64_create(UInt64(UInt32.min)))
		try assert(   0 as UInt32, encodesEqualTo: xpc_uint64_create(                 0))
		try assert( 123 as UInt32, encodesEqualTo: xpc_uint64_create(               123))
		try assert(.max as UInt32, encodesEqualTo: xpc_uint64_create(UInt64(UInt32.max)))
	}
	
	func testEncodes_UInt64_as_XPCUInt64() throws {
		try assert(.min as UInt64, encodesEqualTo: xpc_uint64_create(UInt64(UInt64.min)))
		try assert(   0 as UInt64, encodesEqualTo: xpc_uint64_create(                 0))
		try assert( 123 as UInt64, encodesEqualTo: xpc_uint64_create(               123))
		try assert(.max as UInt64, encodesEqualTo: xpc_uint64_create(UInt64(UInt64.max)))
	}
	
	// MARK: Floating point numbers
	
	func testEncodes_Float_as_XPCDouble() throws {
		// "Normal" values, from lowest to highest
		try assert(-Float.infinity,                encodesEqualTo: xpc_double_create(Double(-Float.infinity)))
		try assert(-Float.greatestFiniteMagnitude, encodesEqualTo: xpc_double_create(Double(-Float.greatestFiniteMagnitude)))
		try assert(-123.0 as Float,                encodesEqualTo: xpc_double_create(-123.0))
		try assert(-Float.leastNormalMagnitude,    encodesEqualTo: xpc_double_create(Double(-Float.leastNormalMagnitude)))
		try assert(-Float.leastNonzeroMagnitude,   encodesEqualTo: xpc_double_create(Double(-Float.leastNonzeroMagnitude)))
		try assert(-0.0 as Float,                  encodesEqualTo: xpc_double_create(-0.0))
		try assert(0.0 as Float,                   encodesEqualTo: xpc_double_create(0.0))
		try assert(Float.leastNonzeroMagnitude,    encodesEqualTo: xpc_double_create(Double(Float.leastNonzeroMagnitude)))
		try assert(Float.leastNormalMagnitude,     encodesEqualTo: xpc_double_create(Double(Float.leastNormalMagnitude)))
		try assert(123.0 as Float,                 encodesEqualTo: xpc_double_create(123.0))
		try assert(Float.greatestFiniteMagnitude,  encodesEqualTo: xpc_double_create(Double(Float.greatestFiniteMagnitude)))
		try assert(Float.infinity,                 encodesEqualTo: xpc_double_create(Double(Float.infinity)))
		
		// NaN
		let result = xpc_double_get_value(try encode(Float.nan))
		XCTAssert(result.isNaN)
	}
	
	func testEncodes_Float_SignalingNaN_as_XPCDouble_SignalingNaN() throws {
		let result = xpc_double_get_value(try encode(Float.signalingNaN))
		XCTAssert(result.isNaN)
        XCTAssertTrue(result.isSignalingNaN)
	}
	
	func testEncodes_Double_as_XPCDouble() throws {
		// "Normal" values, from lowest to highest
		try assert(-Double.infinity,                encodesEqualTo: xpc_double_create(-Double.infinity))
		try assert(-Double.greatestFiniteMagnitude, encodesEqualTo: xpc_double_create(-Double.greatestFiniteMagnitude))
		try assert(-123.0 as Float,                 encodesEqualTo: xpc_double_create(-123.0))
		try assert(-Double.leastNormalMagnitude,    encodesEqualTo: xpc_double_create(-Double.leastNormalMagnitude))
		try assert(-Double.leastNonzeroMagnitude,   encodesEqualTo: xpc_double_create(-Double.leastNonzeroMagnitude))
		try assert(-0.0 as Float,                   encodesEqualTo: xpc_double_create(-0.0))
		try assert(0.0 as Float,                    encodesEqualTo: xpc_double_create(0.0))
		try assert(Double.leastNonzeroMagnitude,    encodesEqualTo: xpc_double_create(Double.leastNonzeroMagnitude))
		try assert(Double.leastNormalMagnitude,     encodesEqualTo: xpc_double_create(Double.leastNormalMagnitude))
		try assert(123.0 as Float,                  encodesEqualTo: xpc_double_create(123.0))
		try assert(Double.greatestFiniteMagnitude,  encodesEqualTo: xpc_double_create(Double.greatestFiniteMagnitude))
		try assert(Double.infinity,                 encodesEqualTo: xpc_double_create(Double.infinity))
		
		// NaN
		let result = xpc_double_get_value(try encode(Double.nan))
		XCTAssert(result.isNaN)
	}
	
	func testEncodes_Double_SignalingNaN_as_XPCDouble_SignalingNaN() throws {
		let result = xpc_double_get_value(try encode(Double.signalingNaN))
		XCTAssert(result.isNaN)
		XCTAssert(result.isSignalingNaN)
	}
	
	// MARK: Misc. types
	
	func testEncodes_Bool_as_XPCBool() throws {
		try assert(false, encodesEqualTo: xpc_bool_create(false))
		try assert(true, encodesEqualTo: xpc_bool_create(true))
		try assert(false, encodesEqualTo: XPC_BOOL_FALSE)
		try assert(true, encodesEqualTo: XPC_BOOL_TRUE)
	}
	
	func testEncodes_String_as_XPCString() throws {
		try assert("", encodesEqualTo: xpc_string_create(""))
		try assert("Hello, world!", encodesEqualTo: xpc_string_create("Hello, world!"))
	}
	
	func testEncodes_NilValues_as_XPCNull() throws {
		let xpcNull = xpc_null_create()
		
		// Signed integers
		try assert(nil as Int?, encodesEqualTo: xpcNull)
		try assert(nil as Int8?, encodesEqualTo: xpcNull)
		try assert(nil as Int16?, encodesEqualTo: xpcNull)
		try assert(nil as Int32?, encodesEqualTo: xpcNull)
		try assert(nil as Int64?, encodesEqualTo: xpcNull)
		
		// Unsigned integers
		try assert(nil as UInt?, encodesEqualTo: xpcNull)
		try assert(nil as UInt8?, encodesEqualTo: xpcNull)
		try assert(nil as UInt16?, encodesEqualTo: xpcNull)
		try assert(nil as UInt32?, encodesEqualTo: xpcNull)
		try assert(nil as UInt64?, encodesEqualTo: xpcNull)
		
		// Floating point numbers
		try assert(nil as Float?, encodesEqualTo: xpcNull)
		try assert(nil as Double?, encodesEqualTo: xpcNull)
		
		// Misc. types
		try assert(nil as Bool?, encodesEqualTo: xpcNull)
		try assert(nil as String?, encodesEqualTo: xpcNull)
	}
}
