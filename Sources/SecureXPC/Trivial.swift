//
//  Trivial.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-20
//


/// Types conforming to this protocol are trivial.
///
/// A _trivial_ type can be copied bit for bit with no indirection or reference-counting operations. Generally, native Swift types that do not contain strong or weak
/// references or other forms of indirection are trivial, as are imported C structs and enums. A trivial type will return `true` when provided to the built-in function
/// `_isPOD(_:)`.
public protocol Trivial {}

// For more details see:
// - Discussion: https://forums.swift.org/t/trying-to-understand-pod-plain-old-datatypes/49738/3
// - Documentation: https://github.com/apple/swift/blob/main/docs/ABIStabilityManifesto.md#type-properties

extension Bool: Trivial {}
extension Double: Trivial {}
extension Float: Trivial {}
extension UInt: Trivial {}
extension UInt8: Trivial {}
extension UInt16: Trivial {}
extension UInt32: Trivial {}
extension UInt64: Trivial {}
extension Int: Trivial {}
extension Int8: Trivial {}
extension Int16: Trivial {}
extension Int32: Trivial {}
extension Int64: Trivial {}
