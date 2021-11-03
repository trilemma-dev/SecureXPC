//
//  TestHelpers.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-03.
//

import XCTest
@testable import SecureXPC

// MARK: Encoding entry point

func encode<T: Encodable>(_ input: T) throws -> xpc_object_t {
	try XPCEncoder.encode(input)
}

// MARK: Assertions


/// Assert that the provided `input`, when encoded using an XPCEncoder, is equal to the `expected` XPC Object
func assert<T: Encodable>(
	_ input: T,
	encodesEqualTo expected: xpc_object_t,
	file: StaticString = #file,
	line: UInt = #line
) throws {
	let actual = try encode(input)
	assertEqual(actual, expected, file: file, line: line)
}

/// Asserts that `actual` and `expected` are value-equal, according to `xpc_equal`
///
/// `-[OS_xpc_object isEqual]` exists, but it uses object-identity as the basis for equality, which is not what we want here.
fileprivate func assertEqual(
	_ actual: xpc_object_t,
	_ expected: xpc_object_t,
	file: StaticString = #file,
	line: UInt = #line
) {
	if !xpc_equal(expected, actual) {
		XCTFail("\(actual) is not equal to \(expected).", file: file, line: line)
	}
}
