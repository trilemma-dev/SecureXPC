//
//  Server Termination Integration Test.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-01-10
//

import XCTest
@testable import SecureXPC

class ServerTerminationIntegrationTest: XCTestCase {

    let dummyRequirements: [SecRequirement] = {
        var requirement: SecRequirement?
        // This is a worthless security requirement which should always result in the connection being accepted
        SecRequirementCreateWithString("info [CFBundleVersion] exists" as CFString, SecCSFlags(), &requirement)
        
        return [requirement!]
    }()
    
    // This test is intended to simulate a server running in a different process and then that process terminating
    func testShutdownServer() async throws {
        // Server & client setup
        let route = XPCRoute.named("doNothing")
        let server = XPCServer.makeAnonymous(clientRequirements: dummyRequirements)
        server.registerRoute(route) { }
        server.start()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        // Send a message, which will result in the connection being established with the server
        try await client.send(toRoute: route)
        
        // Shut down the server, simulating the scenario of the process containing the server terminating
        (server as! XPCAnonymousServer).simulateDisconnectionForTesting()
        
        let interruptedExpectation = self.expectation(description: "Second message results in an interrupted error")
        do {
            try await client.send(toRoute: route)
        } catch {
            switch error {
                case XPCError.connectionInterrupted:
                    interruptedExpectation.fulfill()
                default:
                    XCTFail("Unexpected error: \(error). \(XPCError.connectionInterrupted) should have been thrown.")
            }
        }
        
        let cannotBeReestablishedExpectation = self.expectation(description: "Third message can't establish connection")
        do {
            try await client.send(toRoute: route)
        } catch {
            switch error {
                case XPCError.connectionCannotBeReestablished:
                    cannotBeReestablishedExpectation.fulfill()
                default:
                    XCTFail("Unexpected error: \(error). \(XPCError.connectionCannotBeReestablished) should have " +
                            "been thrown.")
            }
        }
        
        await self.waitForExpectations(timeout: 1)
    }
}
