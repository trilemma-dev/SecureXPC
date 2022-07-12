//
//  XPCCoderError.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-12
//

/// Thrown by a "fake" `Codable` instance such as ``XPCServerEndpoint`` or ``IOSurfaceForXPC`` which are only capable of being encoded or
/// decoded by the XPC coders, not an arbitrary coder.
///
/// This error is intentionally internal to this package as we don't want API users to be trying to explicitly handle this specific case.
enum XPCCoderError: Error {
    case onlyDecodableBySecureXPC
    case onlyEncodableBySecureXPC
}
