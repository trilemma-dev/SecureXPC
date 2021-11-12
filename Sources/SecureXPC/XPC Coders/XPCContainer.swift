//
//  XPCContainer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation


internal protocol XPCContainer {
	func encodedValue() throws -> xpc_object_t?
}

internal struct XPCObject: XPCContainer {
	let object: xpc_object_t

	func encodedValue() throws -> xpc_object_t? {
		return object
	}
}
