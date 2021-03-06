//
//  TestHelpers.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-03.
//

import XCTest
@testable import SecureXPC

// MARK: Encoding/Decoding

func encode<T: Encodable>(_ input: T) throws -> xpc_object_t {
	try XPCEncoder.encode(input)
}

func decode<T: Decodable>(_ input: xpc_object_t) throws -> T {
	try XPCDecoder.decode(T.self, object: input)
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

/// Assert that the provided `input`, when decoded using an XPCDecoder, is equal to the `expected` Swift value
func assert<T: Decodable & Equatable>(
	_ input: xpc_object_t,
	decodesEqualTo expected: T,
	file: StaticString = #file,
	line: UInt = #line
) throws {
	let actual = try decode(input) as T
	XCTAssertEqual(actual, expected, file: file, line: line)
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

/// Asserts that `value` is equal to the result of encoding and then decoding `value`
func assertRoundTripEqual<T: Codable & Equatable>(_ value: T, file: StaticString = #file, line: UInt = #line) throws {
    let encodedValue = try XPCEncoder.encode(value)
    let decodedValue = try XPCDecoder.decode(T.self, object: encodedValue)
    
    XCTAssertEqual(value, decodedValue, file: file, line: line)
}

// MARK: XPC object factories

/// Converts the provided `sourceArray` into an XPC array, by transforming its non-nil elements by the provided `transformIntoXPCObject` closure,
/// and replacing `nil` values with the proper XPC null object.
/// - Parameters:
///   - sourceArray: The values to transform and pack into the XPC array
///   - transformIntoXPCObject: The closures used to transform the non-nil source elements into XPC objects
/// - Returns: an XPC array containing the transformed XPC objects
func createXPCArray<T>(from sourceArray: [T?], using transformIntoXPCObject: (T) -> xpc_object_t) -> xpc_object_t {
	let xpcArray = xpc_array_create(nil, 0)
	
	for element in sourceArray {
		let xpcObject = element.map { transformIntoXPCObject($0) } ?? xpc_null_create()
		xpc_array_append_value(xpcArray, xpcObject)
	}
	
	return xpcArray
}

protocol XPCCodableFixedSize {}
extension Int: XPCCodableFixedSize {}
extension Int8: XPCCodableFixedSize {}
extension Int16: XPCCodableFixedSize {}
extension Int32: XPCCodableFixedSize {}
extension Int64: XPCCodableFixedSize {}
extension UInt: XPCCodableFixedSize {}
extension UInt8: XPCCodableFixedSize {}
extension UInt16: XPCCodableFixedSize {}
extension UInt32: XPCCodableFixedSize {}
extension UInt64: XPCCodableFixedSize {}
extension Float: XPCCodableFixedSize {}
extension Double: XPCCodableFixedSize {}
extension Bool: XPCCodableFixedSize {}

/// Converts the provided `sourceArray` into an XPC data instance. This only works for fixed size types which conform to `XPCCodableFixedSize` (which
/// is intentionally only a concept for test code and does not exist in the framework itself).
///
/// - Parameters:
///   - sourceArray: The values to encode into an XPC data instance.
/// - Returns: An XPC data instance containing the array.
func createXPCData<T: XPCCodableFixedSize & Codable>(fromArray sourceArray: [T]) -> xpc_object_t {
    return sourceArray.withUnsafeBytes { rawByteBuffer in
        xpc_data_create(rawByteBuffer.baseAddress!, rawByteBuffer.count)
    }
}

/// Converts the provided `sourceDict` into an XPC dictionary, by transforming its non-nil values by the provided `transformIntoXPCObject` closure,
/// and replacing `nil` values with the proper XPC null object.
/// - Parameters:
///   - sourceDict: The values to transform and pack into the XPC dictionary
///   - transformIntoXPCObject: The closures used to transform the non-nil source elements into XPC objects
/// - Returns: an XPC dictionary containing the transformed XPC objects
func createXPCDict<V>(from sourceDict: [String: V?], using wrapIntoXPCObject: (V) -> xpc_object_t) -> xpc_object_t {
	let xpcDict = xpc_dictionary_create(nil, nil, 0)
	
	for (key, value) in sourceDict {
		let xpcValue = value.map(wrapIntoXPCObject) ?? xpc_null_create()
		
		key.withCString { keyP in
			xpc_dictionary_set_value(xpcDict, keyP, xpcValue)
		}
	}
	
	return xpcDict
}
