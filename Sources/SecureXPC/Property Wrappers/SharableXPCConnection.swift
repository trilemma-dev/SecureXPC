//
//  SharableXPCConnection.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-09.
//

import Foundation


@propertyWrapper
public struct SharableXPCConnection {
	public let wrappedValue: xpc_connection_t

	public init(wrappedValue: xpc_connection_t) {
		self.wrappedValue = wrappedValue
	}

	enum Error: Swift.Error {
		case incompatibleEncoder, incompatibleDecoder

		var localizedDescription: String {
			switch self {
			case .incompatibleEncoder: return "A @SharableXPCConnection `xpc_connection_t` can only be encoded SecureXPC."
			case .incompatibleDecoder: return "A @SharableXPCConnection `xpc_connection_t` can only be decoded SecureXPC."
			}
		}
	}
}

extension SharableXPCConnection: Equatable {
	public static func == (lhs: Self, rhs: Self) -> Bool {
		xpc_equal(lhs.wrappedValue, rhs.wrappedValue)
	}
}

extension SharableXPCConnection: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(xpc_hash(self.wrappedValue))
	}
}

extension SharableXPCConnection: Encodable {
	public func encode(to encoder: Encoder) throws {
		guard let xpcEncoder = encoder as? XPCEncoderImpl else { throw Error.incompatibleEncoder }

		let container = xpcEncoder.singleValueContainer() as! XPCSingleValueEncodingContainer

		container.encode(xpcConnection: self.wrappedValue)
	}
}

extension SharableXPCConnection: Decodable {
	public init(from decoder: Decoder) throws {
		guard let xpcDecoder = decoder as? XPCDecoderImpl else { throw Error.incompatibleDecoder }

		let container = try xpcDecoder.singleValueContainer() as! XPCSingleValueDecodingContainer

		self.init(wrappedValue: try container.decodeXPCConnection())
	}
}

struct ExampleUsage: Equatable, Hashable, Encodable, Decodable {
	init() { fatalError("stub") }

	// Must be `var` otherwise you get:
	// ❌ Property wrapper can only be applied to a 'var'
	@SharableXPCConnection
	var c: xpc_connection_t
}
