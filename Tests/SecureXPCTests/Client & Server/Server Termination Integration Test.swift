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
    func testShutdownServer() throws {
        // Server & client setup
        let echoRoute = XPCRouteWithMessageWithReply("echo", messageType: String.self, replyType: String.self)
        let server = XPCServer.makeAnonymous(clientRequirements: dummyRequirements)
        try server.registerRoute(echoRoute) { msg in
            return "echo: \(msg)"
        }
        server.start()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        // Send a message, which will result in the connection being established with the server
        client.sendMessage("1st message", route: echoRoute) { _ in }
        
        // Shut down the server, simulating the scenario of the process containing the server terminating
        (server as! XPCAnonymousServer).simulateDisconnectionForTesting()
        
        // Make two more calls after having shutdown the server:
        // - The second call should fail upon trying to send the message, connection is interrupted
        // - The third call (and any subsequent ones) should fail indicating no new connections can ever be established
        let interruptedExpectation = self.expectation(description: "Second message results in an interrupted error")
        let cannotBeReestablishedExpectation = self.expectation(description: "Third message can't be sent")
        client.sendMessage("2nd message", route: echoRoute) { response in
            switch response {
                case .failure(.connectionInterrupted):
                    interruptedExpectation.fulfill()
                    
                    // make another call to the server and this should fail with connectionCannotBeReestablished
                    client.sendMessage("3rd message", route: echoRoute) { response in
                        switch response {
                            case .failure(.connectionCannotBeReestablished):
                                cannotBeReestablishedExpectation.fulfill()
                            case .failure(let error):
                                XCTFail("Unexpected error: \(error). \(XPCError.connectionCannotBeReestablished) " +
                                        "should have been returned.")
                            case .success(_):
                                XCTFail("No error was returned. \(XPCError.connectionCannotBeReestablished) should " +
                                        "have been returned.")
                        }
                    }
                case .failure(let error):
                    XCTFail("Unexpected error: \(error). \(XPCError.connectionInterrupted) should have been returned.")
                case .success(_):
                    XCTFail("No error was returned. \(XPCError.connectionInterrupted) should have been returned.")
            }
        }
        
        self.waitForExpectations(timeout: 1)
    }
}
