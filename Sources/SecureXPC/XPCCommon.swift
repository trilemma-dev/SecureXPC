//
//  XPCCommon.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// A key into the XPC dictionary.
///
/// Instances of this type are part of the "packaging" format used by `Request` and `Response`.
typealias XPCDictionaryKey = UnsafePointer<CChar>

/// A helper function for defining C string constants, intended to have static lifetime.
/// - Parameter input: The input string literal, which will be copied into the result.
/// - Returns: A C string which can be stored indefinitely.
func const(_ input: UnsafePointer<CChar>!) -> UnsafePointer<CChar>! {
	let mutableCopy = strdup(input)!
	return UnsafePointer(mutableCopy) // The result should never actually be mutated
}
