//
//  File.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-12.
//

import Foundation

/// Convenience extension to improve quality of error descriptions
internal extension xpc_type_t {
	var description: String {
		switch self {
			case XPC_TYPE_ARRAY:
				return "array"
			case XPC_TYPE_DICTIONARY:
				return "dictionary"
			case XPC_TYPE_BOOL:
				return "bool"
			case XPC_TYPE_DATA:
				return "data"
			case XPC_TYPE_DATE:
				return "date"
			case XPC_TYPE_DOUBLE:
				return "double"
			case XPC_TYPE_INT64:
				return "int64"
			case XPC_TYPE_STRING:
				return "string"
			case XPC_TYPE_UINT64:
				return "unit64"
			case XPC_TYPE_UUID:
				return "uuid"
			case XPC_TYPE_ACTIVITY:
				return "activity"
			case XPC_TYPE_ENDPOINT:
				return "endpoint"
			case XPC_TYPE_ERROR:
				return "error"
			case XPC_TYPE_FD:
				return "file descriptor"
			case XPC_TYPE_SHMEM:
				return "shared memory"
			case XPC_TYPE_CONNECTION:
				return "connection"
			case XPC_TYPE_NULL:
				return "null"
			default:
				return "unknown"
		}
	}
}
