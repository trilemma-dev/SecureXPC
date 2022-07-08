//
//  Server Identity Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-07
//

import Foundation
import XCTest
@testable import SecureXPC

class ServerIdentityTests: XCTestCase {
    func testGetServerIdentity() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.start()
        
        // Since the server is running in the same process as this test, the identity should be the same as this one
        var currentCode: SecCode?
        SecCodeCopySelf([], &currentCode)
        
        let serverIdentity = try await client.serverIdentity
        XCTAssertEqual(serverIdentity.code, currentCode!)
        XCTAssertEqual(serverIdentity.effectiveUserID, geteuid())
        XCTAssertEqual(serverIdentity.effectiveGroupID, getegid())
        XCTAssertEqual(serverIdentity.processID, getpid())
    }
}
