//
//  XPCServerEndpoint.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import Foundation

/// An endpoint is used to create clients which can communicate with their associated server.
///
/// Endpoints are retrieved from a server's ``XPCNonBlockingServer/endpoint`` property. They can be used in the same process or sent across an existing XPC
/// connection.
///
/// > Warning: While ``XPCServerEndpoint`` conforms to `Codable` it can only be encoded and decoded by the `SecureXPC` framework.
public struct XPCServerEndpoint {
    // Technically, an `xpc_endpoint_t` is sufficient to create a new connection, on its own. However, it's useful to
    // be able to communicate the kind of connection, and its name, so we also store those, separately.
    internal let serviceDescriptor: XPCServiceDescriptor
    internal let endpoint: xpc_endpoint_t

    internal init(serviceDescriptor: XPCServiceDescriptor, endpoint: xpc_endpoint_t) {
        self.serviceDescriptor = serviceDescriptor
        self.endpoint = endpoint
    }
}

extension XPCServerEndpoint: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(xpc_hash(self.endpoint))
    }
}

extension XPCServerEndpoint: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        // No need to compare service descriptors as the endpoint is guaranteed to be unique
        xpc_equal(lhs.endpoint, rhs.endpoint)
    }
}

// MARK: Codable

private enum CodingKeys: String, CodingKey {
    case serviceDescriptor
    case endpoint
}

extension XPCServerEndpoint: Encodable {
    public func encode(to encoder: Encoder) throws {
        guard let xpcEncoder = encoder as? XPCEncoderImpl else {
            throw XPCServerEndpointError.onlyEncodableBySecureXPCFramework
        }
        
        let container = xpcEncoder.xpcContainer(keyedBy: CodingKeys.self)
        try container.encode(self.serviceDescriptor, forKey: CodingKeys.serviceDescriptor)
        container.encode(self.endpoint, forKey: CodingKeys.endpoint)
    }
}

extension XPCServerEndpoint: Decodable {
    public init(from decoder: Decoder) throws {
        guard let xpcDecoder = decoder as? XPCDecoderImpl else {
            throw XPCServerEndpointError.onlyDecodableBySecureXPCFramework
        }
        
        let container = try xpcDecoder.xpcContainer(keyedBy: CodingKeys.self)
        self.endpoint = try container.decodeEndpoint(forKey: CodingKeys.endpoint)
        self.serviceDescriptor = try container.decode(XPCServiceDescriptor.self, forKey: CodingKeys.serviceDescriptor)
    }
}

private enum XPCServerEndpointError: Error {
    case onlyDecodableBySecureXPCFramework
    case onlyEncodableBySecureXPCFramework
}
