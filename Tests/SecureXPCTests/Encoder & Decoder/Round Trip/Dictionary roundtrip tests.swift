//
//  Dictionary roundtrip tests.swift
//  
//
//  Created by Josh Kaplan on 2021-11-14
//

import XCTest
@testable import SecureXPC

final class XPCDictionaryRoundTripTests: XCTestCase {

    // MARK: Signed Integers
    
    func testRoundTrip_dictOf_SignedIntegers() throws {
        let dictOfInt:   [String: Int  ] = ["int"  : 123]
        let dictOfInt8:  [String: Int8 ] = ["int8" : 123]
        let dictOfInt16: [String: Int16] = ["int16": 123]
        let dictOfInt32: [String: Int32] = ["int32": 123]
        let dictOfInt64: [String: Int64] = ["int64": 123]
        
        try assertRoundTripEqual(dictOfInt)
        try assertRoundTripEqual(dictOfInt8)
        try assertRoundTripEqual(dictOfInt16)
        try assertRoundTripEqual(dictOfInt32)
        try assertRoundTripEqual(dictOfInt64)
    }
    
    func testRoundTrip_dictOf_UnsignedIntegers() throws {
        let dictOfUInt:   [String: UInt  ] = ["uint"  : 123]
        let dictOfUInt8:  [String: UInt8 ] = ["uint8" : 123]
        let dictOfUInt16: [String: UInt16] = ["uint16": 123]
        let dictOfUInt32: [String: UInt32] = ["uint32": 123]
        let dictOfUInt64: [String: UInt64] = ["uint64": 123]
        
        try assertRoundTripEqual(dictOfUInt)
        try assertRoundTripEqual(dictOfUInt8)
        try assertRoundTripEqual(dictOfUInt16)
        try assertRoundTripEqual(dictOfUInt32)
        try assertRoundTripEqual(dictOfUInt64)
    }
    
    // MARK: Floating point numbers
    
    func testRoundTrip_dictOf_Floats() throws {
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
        
        try assertRoundTripEqual(dictOfFloats)
        
        // These don't have regular equality, so we'll check them seperately.
        let nans = ["nan": Float.nan, "signalingNaN": Float.signalingNaN]
        let nansEncoded = try XPCEncoder.encode(nans)
        let nansDecoded = try XPCDecoder.decode([String: Float].self, object: nansEncoded)
        XCTAssertEqual(nans.count, nansDecoded.count)
        XCTAssert(nansDecoded["nan"]!.isNaN)
        XCTAssert(nansDecoded["signalingNaN"]!.isNaN)
        XCTAssert(nansDecoded["signalingNaN"]!.isSignalingNaN)
    }

    func testRoundTrip_dictOf_Doubles() throws {
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
        
        try assertRoundTripEqual(dictOfDoubles)
        
        // These don't have regular equality, so we'll check them seperately.
        let nans = ["nan": Double.nan, "signalingNaN": Double.signalingNaN]
        let nansEncoded = try XPCEncoder.encode(nans)
        let nansDecoded = try XPCDecoder.decode([String: Double].self, object: nansEncoded)
        XCTAssertEqual(nans.count, nansDecoded.count)
        XCTAssert(nansDecoded["nan"]!.isNaN)
        XCTAssert(nansDecoded["signalingNaN"]!.isNaN)
        XCTAssert(nansDecoded["signalingNaN"]!.isSignalingNaN)
    }

    // MARK: Misc. types

    func testRoundTrip_dictOf_Bools() throws {
        let bools = ["false": false, "true": true]
        try assertRoundTripEqual(bools)
    }

    func testRoundTrip_dictOf_Strings() throws {
        let strings = ["empty": "", "string": "Hello, world!"]
        try assertRoundTripEqual(strings)
    }

    func testRoundTrip_dictsOf_Nils() throws {
        // Signed integers
        let dictOfInt:   [String: Optional<Int  >] = ["int"  : 123, "nil": nil]
        let dictOfInt8:  [String: Optional<Int8 >] = ["int8" : 123, "nil": nil]
        let dictOfInt16: [String: Optional<Int16>] = ["int16": 123, "nil": nil]
        let dictOfInt32: [String: Optional<Int32>] = ["int32": 123, "nil": nil]
        let dictOfInt64: [String: Optional<Int64>] = ["int64": 123, "nil": nil]

        try assertRoundTripEqual(dictOfInt)
        try assertRoundTripEqual(dictOfInt8)
        try assertRoundTripEqual(dictOfInt16)
        try assertRoundTripEqual(dictOfInt32)
        try assertRoundTripEqual(dictOfInt64)

        // Unsigned integers
        let dictOfUInt:   [String: Optional<UInt  >] = ["uint"  : 123, "nil": nil]
        let dictOfUInt8:  [String: Optional<UInt8 >] = ["uint8" : 123, "nil": nil]
        let dictOfUInt16: [String: Optional<UInt16>] = ["uint16": 123, "nil": nil]
        let dictOfUInt32: [String: Optional<UInt32>] = ["uint32": 123, "nil": nil]
        let dictOfUInt64: [String: Optional<UInt64>] = ["uint64": 123, "nil": nil]

        try assertRoundTripEqual(dictOfUInt)
        try assertRoundTripEqual(dictOfUInt8)
        try assertRoundTripEqual(dictOfUInt16)
        try assertRoundTripEqual(dictOfUInt32)
        try assertRoundTripEqual(dictOfUInt64)
        
        // Floating point numbers
        let floats: [String: Float?] = ["float": 123, "nil": nil]
        try assertRoundTripEqual(floats)
        let doubles: [String: Double?] = ["double": 123, "nil": nil]
        try assertRoundTripEqual(doubles)
        
        // Misc. types
        let bools = ["false": false, "true": true, "nil": nil]
        try assertRoundTripEqual(bools)

        let strings = ["empty": "", "string": "Hello, world!", "nil": nil]
        try assertRoundTripEqual(strings)
    }

    // MARK: Dictionaries of aggregates

    func testRoundtrip_dictOf_Arrays() throws {
        // There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
        let expectedResultDictOfArrays = [
            "a1": [1, 2, 3],
            "a2": [4, 5, 6],
        ]
        try assertRoundTripEqual(expectedResultDictOfArrays)
    }

    func testRoundtrip_dictOf_Dicts() throws {
        // There's too many possible permutations, but it should be satisfactory to just test one kind of nesting.
        let expectedResultDictOfDicts = [
            "d1": ["a": 1, "b": 2, "c": 3],
            "d2": ["d": 4, "e": 5, "f": 6],
        ]
        try assertRoundTripEqual(expectedResultDictOfDicts)
    }
}

