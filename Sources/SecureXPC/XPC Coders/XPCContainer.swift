//
//  XPCContainer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation


fileprivate protocol XPCContainer {
	func encodedValue() throws -> xpc_object_t?
}

fileprivate struct XPCObject: XPCContainer {
	let object: xpc_object_t

	func encodedValue() throws -> xpc_object_t? {
		return object
	}
}
