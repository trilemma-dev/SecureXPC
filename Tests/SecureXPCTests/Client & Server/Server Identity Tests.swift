//
//  Server Identity Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-07
//

import Foundation
import XCTest
import SecureXPC

class ServerIdentityTests: XCTestCase {
    func testGetServerIdentity() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.start()
        
        // Since the server is running in the same process as this test, the identity should be the same as this one
        var currentIdentity: SecCode?
        SecCodeCopySelf([], &currentIdentity)
        let serverIdentity = try await client.serverIdentity
        XCTAssertEqual(serverIdentity, currentIdentity!)
    }
}
