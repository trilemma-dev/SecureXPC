//
//  XPCMachClient.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// A concrete implementation of ``XPCClient`` which can communicate with a Mach service.
///
/// In the case of this framework, the Mach service is expected to be represented by an `XPCMachServer`.
internal class XPCMachClient: XPCClient {
    /// Creates and returns a connection for the Mach service represented by this client.
    internal override func createConnection() -> xpc_connection_t {
        xpc_connection_create_mach_service(self.serviceName, nil, 0)
    }
}
