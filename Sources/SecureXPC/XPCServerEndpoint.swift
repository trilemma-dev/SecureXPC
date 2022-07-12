//
//  XPCServerEndpoint.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import Foundation

/// An endpoint is used to create clients which can communicate with their associated server.
///
/// Endpoints are retrieved from a server's ``XPCServer/endpoint`` property. They can be used in the same process or sent across an existing XPC
/// connection.
///
/// > Warning: While ``XPCServerEndpoint`` conforms to `Codable` it can only be encoded and decoded by the `SecureXPC` framework.
public struct XPCServerEndpoint {
    // Private implementation note: The connection descriptor may not represent the _true_ connection type in the case
    // of an XPCServiceServer which for its endpoint makes use of an anonymous connection. SecureXPC intentionally
    // represents this an an `xpcService` connection type as it better represents how SecureXPC behaves for the user.
    /// The type of connections serviced by the ``XPCServer`` which created this endpoint.
    public let connectionDescriptor: XPCConnectionDescriptor
    
    // The underlying XPC C API endpoint needed to create connections to the listener connection it came from
    internal let endpoint: xpc_endpoint_t
}

extension XPCServerEndpoint: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(xpc_hash(self.endpoint))
    }
}

extension XPCServerEndpoint: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        // No need to compare connection descriptors as the endpoint is guaranteed to be unique (also all anonymous
        // connection descriptors are equivalent to one another because they don't have names).
        xpc_equal(lhs.endpoint, rhs.endpoint)
    }
}

// MARK: Codable

private enum CodingKeys: String, CodingKey {
    case connectionDescriptor
    case endpoint
}

extension XPCServerEndpoint: Encodable {
    public func encode(to encoder: Encoder) throws {
        let xpcEncoder = try XPCEncoderImpl.asXPCEncoderImpl(encoder)
        let container = xpcEncoder.xpcContainer(keyedBy: CodingKeys.self)
        try container.encode(self.connectionDescriptor, forKey: CodingKeys.connectionDescriptor)
        container.encode(self.endpoint, forKey: CodingKeys.endpoint)
    }
}

extension XPCServerEndpoint: Decodable {
    public init(from decoder: Decoder) throws {
        let xpcDecoder = try XPCDecoderImpl.asXPCDecoderImpl(decoder)
        let container = try xpcDecoder.xpcContainer(keyedBy: CodingKeys.self)
        self.endpoint = try container.decodeEndpoint(forKey: CodingKeys.endpoint)
        self.connectionDescriptor = try container.decode(XPCConnectionDescriptor.self,
                                                         forKey: CodingKeys.connectionDescriptor)
    }
}
