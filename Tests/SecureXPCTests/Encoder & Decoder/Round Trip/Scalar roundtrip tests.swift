//
//  Scalar roundtrip tests.swift
//  
//
//  Created by Josh Kaplan on 2021-11-14
//

import XCTest
@testable import SecureXPC

final class XPCScalarRoundTripTests: XCTestCase {
    // MARK: Signed Integers
    
    func testRoundTrip_Int() throws {
        try assertRoundTripEqual(Int.min)
        try assertRoundTripEqual(-123 as Int)
        try assertRoundTripEqual(0 as Int)
        try assertRoundTripEqual(123 as Int)
        try assertRoundTripEqual(Int.max)
    }
    
    func testRoundTrip_Int8() throws {
        try assertRoundTripEqual(Int8.min)
        try assertRoundTripEqual(-123 as Int8)
        try assertRoundTripEqual(0 as Int8)
        try assertRoundTripEqual(123 as Int8)
        try assertRoundTripEqual(Int8.max)
    }
    
    func testRoundTrip_Int16() throws {
        try assertRoundTripEqual(Int16.min)
        try assertRoundTripEqual(-123 as Int16)
        try assertRoundTripEqual(0 as Int16)
        try assertRoundTripEqual(123 as Int16)
        try assertRoundTripEqual(Int16.max)
    }
    
    func testRoundTrip_Int32() throws {
        try assertRoundTripEqual(Int32.min)
        try assertRoundTripEqual(-123 as Int32)
        try assertRoundTripEqual(0 as Int32)
        try assertRoundTripEqual(123 as Int32)
        try assertRoundTripEqual(Int32.max)
    }
    
    func testRoundTrip_Int64() throws {
        try assertRoundTripEqual(Int64.min)
        try assertRoundTripEqual(-123 as Int64)
        try assertRoundTripEqual(0 as Int64)
        try assertRoundTripEqual(123 as Int64)
        try assertRoundTripEqual(Int64.max)
    }
    
    // MARK: Unsigned Integers
    
    func testRoundTrip_UInt() throws {
        try assertRoundTripEqual(UInt.min)
        try assertRoundTripEqual(0 as UInt)
        try assertRoundTripEqual(123 as UInt)
        try assertRoundTripEqual(UInt.max)
    }
    
    func testRoundTrip_UInt8() throws {
        try assertRoundTripEqual(UInt8.min)
        try assertRoundTripEqual(0 as UInt8)
        try assertRoundTripEqual(123 as UInt8)
        try assertRoundTripEqual(UInt8.max)
    }
    
    func testRoundTrip_UInt16() throws {
        try assertRoundTripEqual(UInt16.min)
        try assertRoundTripEqual(0 as UInt16)
        try assertRoundTripEqual(123 as UInt16)
        try assertRoundTripEqual(UInt16.max)
    }
    
    func testRoundTrip_UInt32() throws {
        try assertRoundTripEqual(UInt32.min)
        try assertRoundTripEqual(0 as UInt32)
        try assertRoundTripEqual(123 as UInt32)
        try assertRoundTripEqual(UInt32.max)
    }
    
    func testRoundTrip_UInt64() throws {
        try assertRoundTripEqual(UInt64.min)
        try assertRoundTripEqual(0 as UInt64)
        try assertRoundTripEqual(123 as UInt64)
        try assertRoundTripEqual(UInt64.max)
    }
    
    // MARK: Floating point numbers
    
    func testRoundTrip_Float() throws {
        // "Normal" values, from lowest to highest
        try assertRoundTripEqual(-Float.infinity)
        try assertRoundTripEqual(-Float.greatestFiniteMagnitude)
        try assertRoundTripEqual(-123.0 as Float)
        try assertRoundTripEqual(-Float.leastNormalMagnitude)
        try assertRoundTripEqual(-Float.leastNonzeroMagnitude)
        try assertRoundTripEqual(-0.0 as Float)
        try assertRoundTripEqual(0.0 as Float)
        try assertRoundTripEqual(Float.leastNonzeroMagnitude)
        try assertRoundTripEqual(Float.leastNormalMagnitude)
        try assertRoundTripEqual(123.0 as Float)
        try assertRoundTripEqual(Float.greatestFiniteMagnitude)
        try assertRoundTripEqual(Float.infinity)
        
        // NaN
        let nan = Float.nan
        let nanEncoded = try XPCEncoder.encode(nan)
        let nanDecoded = try XPCDecoder.decode(Float.self, object: nanEncoded)
        XCTAssert(nanDecoded.isNaN)
        
        // Signaling NaN
        let signalingNaN = Float.signalingNaN
        let signalingNaNEncoded = try XPCEncoder.encode(signalingNaN)
        let signalingNaNDecoded = try XPCDecoder.decode(Float.self, object: signalingNaNEncoded)
        XCTAssert(signalingNaNDecoded.isNaN)
        XCTAssert(signalingNaNDecoded.isSignalingNaN)
    }
    
    func testRoundTrip_Double() throws {
        // "Normal" values, from lowest to highest
        try assertRoundTripEqual(-Double.infinity)
        try assertRoundTripEqual(-Double.greatestFiniteMagnitude)
        try assertRoundTripEqual(-123.0 as Double)
        try assertRoundTripEqual(-Double.leastNormalMagnitude)
        try assertRoundTripEqual(-Double.leastNonzeroMagnitude)
        try assertRoundTripEqual(-0.0 as Double)
        try assertRoundTripEqual(0.0 as Double)
        try assertRoundTripEqual(Double.leastNonzeroMagnitude)
        try assertRoundTripEqual(Double.leastNormalMagnitude)
        try assertRoundTripEqual(123.0 as Double)
        try assertRoundTripEqual(Double.greatestFiniteMagnitude)
        try assertRoundTripEqual(Double.infinity)
        
        // NaN
        let nan = Double.nan
        let nanEncoded = try XPCEncoder.encode(nan)
        let nanDecoded = try XPCDecoder.decode(Double.self, object: nanEncoded)
        XCTAssert(nanDecoded.isNaN)
        
        // Signaling NaN
        let signalingNaN = Double.signalingNaN
        let signalingNaNEncoded = try XPCEncoder.encode(signalingNaN)
        let signalingNaNDecoded = try XPCDecoder.decode(Double.self, object: signalingNaNEncoded)
        XCTAssert(signalingNaNDecoded.isNaN)
        XCTAssert(signalingNaNDecoded.isSignalingNaN)
    }
    
    // MARK: Misc. types
    
    func testRoundTrip_Bool() throws {
        try assertRoundTripEqual(true)
        try assertRoundTripEqual(false)
    }
    
    func testRoundTrip_String() throws {
        try assertRoundTripEqual("")
        try assertRoundTripEqual("Hello, world!")
    }
    
    func testRoundTrip_NilValues() throws {
        // Signed integers
        try assertRoundTripEqual(nil as Int?)
        try assertRoundTripEqual(nil as Int8?)
        try assertRoundTripEqual(nil as Int16?)
        try assertRoundTripEqual(nil as Int32?)
        try assertRoundTripEqual(nil as Int64?)
        
        // Unsigned integers
        try assertRoundTripEqual(nil as UInt?)
        try assertRoundTripEqual(nil as UInt8?)
        try assertRoundTripEqual(nil as UInt16?)
        try assertRoundTripEqual(nil as UInt32?)
        try assertRoundTripEqual(nil as UInt64?)
        
        // Floating point numbers
        try assertRoundTripEqual(nil as Float?)
        try assertRoundTripEqual(nil as Double?)
        
        // Misc. types
        try assertRoundTripEqual(nil as Bool?)
        try assertRoundTripEqual(nil as String?)
    }
}
