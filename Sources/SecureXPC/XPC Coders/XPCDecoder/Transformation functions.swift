//
//  Transformation functions.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

private func baseDecode<T>(value: xpc_object_t,
						   xpcType: xpc_type_t,
						   transform: (xpc_object_t) throws -> T,
						   codingPath: [CodingKey]) throws -> T {
	if xpc_get_type(value) == xpcType {
		return try transform(value)
	} else {
		let debugDescription = "Actual: \(xpc_get_type(value).description), expected: \(String(describing: T.self))"
		let context = DecodingError.Context(codingPath: codingPath,
											debugDescription: debugDescription,
											underlyingError: nil)
		throw DecodingError.typeMismatch(T.self, context)
	}
}

private func intTransform<T: FixedWidthInteger & SignedInteger>(_ type: T.Type,
																codingPath: [CodingKey]) -> (xpc_object_t) throws -> T {
	return { (object: xpc_object_t) in
		let value = xpc_int64_get_value(object)
		if value >= T.min && value <= T.max {
			return T(value)
		} else {
			let description = "\(value) out of range for \(String(describing: T.self)). Min: \(T.min), max: \(T.max)."
			let context = DecodingError.Context(codingPath: codingPath,
												debugDescription: description,
												underlyingError: nil)
			throw DecodingError.typeMismatch(T.self, context)
		}
	}
}

private func uintTransform<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type,
																   codingPath: [CodingKey]) -> (xpc_object_t) throws -> T {
	return { (object: xpc_object_t) in
		let value = xpc_uint64_get_value(object)
		if value <= T.max {
			return T(value)
		} else {
			let description = "\(value) out of range for \(String(describing: T.self)). Max: \(T.max)."
			let context = DecodingError.Context(codingPath: codingPath,
												debugDescription: description,
												underlyingError: nil)
			throw DecodingError.typeMismatch(T.self, context)
		}
	}
}

private func stringTransform(codingPath: [CodingKey]) -> ((xpc_object_t) throws -> String) {
	return { (object: xpc_object_t) in
		if let stringPointer = xpc_string_get_string_ptr(object) {
			return String(cString: stringPointer)
		} else {
			let context = DecodingError.Context(codingPath: codingPath,
												debugDescription: "Unable to decode string",
												underlyingError: nil)
			throw DecodingError.dataCorrupted(context)
		}
	}
}

private let floatTransform = { (object: xpc_object_t) -> Float in
	// Double.signalingNaN is not converted to Float.signalingNaN when calling Float(...) with a Double so this needs
	// to be done manually
	let doubleValue = xpc_double_get_value(object)
	let floatValue = doubleValue.isSignalingNaN ? Float.signalingNaN : Float(doubleValue)

	return floatValue
}
