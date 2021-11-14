//
//  Unkeyed container roundtrip tests.swift
//  
//
//  Created by Josh Kaplan on 2021-11-14
//

import XCTest
@testable import SecureXPC

/// This type manually implement Codable such that it encodes and decodes itself using an unkeyed container of mixed types, all of which are a fixed size
struct MixedFixedSizeTypesStruct: Codable, Equatable {
    private let first: Float
    private let second: Int
    private let third: Int16
    private let fourth: Bool
    
    init() {
        self.first = 5.0
        self.second = 2
        self.third = 4
        self.fourth = true
    }
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.first = try container.decode(Float.self)
        self.second = try container.decode(Int.self)
        self.third = try container.decode(Int16.self)
        self.fourth = try container.decode(Bool.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.first)
        try container.encode(self.second)
        try container.encode(self.third)
        try container.encode(self.fourth)
    }
}

/// This type manually implement Codable such that it encodes and decodes itself using an unkeyed container of mixed types.
/// 
/// The last of these is a String which is variable in size.
struct MixedVariableSizeTypesStruct: Codable, Equatable {
    private let first: Float
    private let second: Int
    private let third: Int16
    private let fourth: Bool
    private let fifth: String
    
    init() {
        self.first = 5.0
        self.second = 2
        self.third = 4
        self.fourth = true
        self.fifth = "Hello World"
    }
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.first = try container.decode(Float.self)
        self.second = try container.decode(Int.self)
        self.third = try container.decode(Int16.self)
        self.fourth = try container.decode(Bool.self)
        self.fifth = try container.decode(String.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.first)
        try container.encode(self.second)
        try container.encode(self.third)
        try container.encode(self.fourth)
        try container.encode(self.fifth)
    }
}

final class XPCUnkeyedContainerRoundTripTests: XCTestCase {
    func testRoundTripMixedFixedSizeTypesStruct() throws {
        try assertRoundTripEqual(MixedFixedSizeTypesStruct())
    }
    
    func testRoundTripMixedVariableSizeTypesStruct() throws {
        try assertRoundTripEqual(MixedVariableSizeTypesStruct())
    }
}
