//
//  Array roundtrip tests.swift
//  
//
//  Created by Josh Kaplan on 2021-11-14
//

import XCTest
@testable import SecureXPC

final class XPCArrayRoundTripTests: XCTestCase {

    // MARK: Signed Integers
    
    func testRoundTrip_arrayOf_SignedIntegers() throws {
        let   ints: [Int  ] = [.min, -123, 0, 123, .max]
        let  int8s: [Int8 ] = [.min, -123, 0, 123, .max]
        let int16s: [Int16] = [.min, -123, 0, 123, .max]
        let int32s: [Int32] = [.min, -123, 0, 123, .max]
        let int64s: [Int64] = [.min, -123, 0, 123, .max]
        
        try assertRoundTripEqual(ints)
        try assertRoundTripEqual(int8s)
        try assertRoundTripEqual(int16s)
        try assertRoundTripEqual(int32s)
        try assertRoundTripEqual(int64s)
    }
    
    func testRoundTrip_arrayOf_UnsignedIntegers() throws {
        let   uints: [UInt  ] = [.min, 0, 123, .max]
        let  uint8s: [UInt8 ] = [.min, 0, 123, .max]
        let uint16s: [UInt16] = [.min, 0, 123, .max]
        let uint32s: [UInt32] = [.min, 0, 123, .max]
        let uint64s: [UInt64] = [.min, 0, 123, .max]
        
        try assertRoundTripEqual(uints)
        try assertRoundTripEqual(uint8s)
        try assertRoundTripEqual(uint16s)
        try assertRoundTripEqual(uint32s)
        try assertRoundTripEqual(uint64s)
    }
    
    // MARK: Floating point numbers
    
    func testRoundTrip_arrayOf_Floats() throws {
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
        
        try assertRoundTripEqual(floats)
        
        // These don't have regular equality, so we'll check them seperately.
        let nans = [Float.nan, Float.signalingNaN]
        let nansEncoded = try XPCEncoder.encode(nans)
        let nansDecoded = try XPCDecoder.decode([Float].self, object: nansEncoded)
        XCTAssertEqual(nans.count, nansDecoded.count)
        XCTAssert(nansDecoded[0].isNaN)
        XCTAssert(nansDecoded[1].isNaN)
        XCTAssert(nansDecoded[1].isSignalingNaN)
    }
    
    func testRoundTrip_arrayOf_Doubles() throws {
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
        
        try assertRoundTripEqual(doubles)
        
        // These don't have regular equality, so we'll check them seperately.
        let nans = [Double.nan, Double.signalingNaN]
        let nansEncoded = try XPCEncoder.encode(nans)
        let nansDecoded = try XPCDecoder.decode([Double].self, object: nansEncoded)
        XCTAssertEqual(nans.count, nansDecoded.count)
        XCTAssert(nansDecoded[0].isNaN)
        XCTAssert(nansDecoded[1].isNaN)
        XCTAssert(nansDecoded[1].isSignalingNaN)
    }
    
    // MARK: Misc. types
    
    func testRoundTrip_arrayOf_Bools() throws {
        let bools = [false, true]
        try assertRoundTripEqual(bools)
    }
    
    func testRoundTrip_arrayOf_Strings() throws {
        let strings = ["", "Hello, world!"]
        try assertRoundTripEqual(strings)
    }
    
    func testRoundTrip_arrayOf_nils() throws {
        // Signed integers
        let   ints: [Optional<Int  >] = [.min, -123, 0, 123, .max, nil]
        let  int8s: [Optional<Int8 >] = [.min, -123, 0, 123, .max, nil]
        let int16s: [Optional<Int16>] = [.min, -123, 0, 123, .max, nil]
        let int32s: [Optional<Int32>] = [.min, -123, 0, 123, .max, nil]
        let int64s: [Optional<Int64>] = [.min, -123, 0, 123, .max, nil]
        
        try assertRoundTripEqual(ints)
        try assertRoundTripEqual(int8s)
        try assertRoundTripEqual(int16s)
        try assertRoundTripEqual(int32s)
        try assertRoundTripEqual(int64s)
        
        // Unsigned integers
        let   uints: [Optional<UInt  >] = [.min, 0, 123, .max, nil]
        let  uint8s: [Optional<UInt8 >] = [.min, 0, 123, .max, nil]
        let uint16s: [Optional<UInt16>] = [.min, 0, 123, .max, nil]
        let uint32s: [Optional<UInt32>] = [.min, 0, 123, .max, nil]
        let uint64s: [Optional<UInt64>] = [.min, 0, 123, .max, nil]
        
        try assertRoundTripEqual(uints)
        try assertRoundTripEqual(uint8s)
        try assertRoundTripEqual(uint16s)
        try assertRoundTripEqual(uint32s)
        try assertRoundTripEqual(uint64s)
        
        // Floating point numbers
        let floats: [Float?] = [-123, 0, 123, nil]
        try assertRoundTripEqual(floats)
        
        let doubles: [Double?] = [-123, 0, 123, nil]
        try assertRoundTripEqual(doubles)
        
        // Misc. types
        let bools = [false, true, nil]
        try assertRoundTripEqual(bools)
        
        let strings = ["", "Hello, world!", nil]
        try assertRoundTripEqual(strings)
    }
    
    // MARK: Arrays of aggregates
    
    func testRoundTrip_arrayOf_Arrays() throws {
        // There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
        let nestedArray = [[1, 2], [3, 4]]
        try assertRoundTripEqual(nestedArray)
    }
    
    func testRoundTrip_arrayOf_Dictionaries() throws {
        // There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
        let arrayOfDicts = [
            ["a": 1, "b": 2, "c": 3],
            ["e": 4, "f": 5, "g": 6],
        ]
        try assertRoundTripEqual(arrayOfDicts)
    }
}
