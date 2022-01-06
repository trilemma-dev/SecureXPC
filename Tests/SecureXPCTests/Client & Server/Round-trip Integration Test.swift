//
//  Round-trip Integration Test.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-28.
//

import XCTest
@testable import SecureXPC

class RoundTripIntegrationTest: XCTestCase {
    var xpcClient: XPCClient! = nil

    static let dummyRequirements: [SecRequirement] = {
        var requirement: SecRequirement?
        // This is a worthless security requirement which should always result in the connection being accepted
        SecRequirementCreateWithString("info [CFBundleVersion] exists" as CFString, SecCSFlags(), &requirement)
        
        return [requirement!]
    }()
    
    let anonymousServer = XPCServer.makeAnonymousService(clientRequirements: RoundTripIntegrationTest.dummyRequirements)

    override func setUp() {
        let endpoint = anonymousServer.endpoint
        xpcClient = XPCClient.forEndpoint(endpoint)

        anonymousServer.start()
    }

    func testSendWithMessageWithReply() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let replyBlockWasCalled = self.expectation(description: "The echo reply was received")

        let echoRoute = XPCRouteWithMessageWithReply("echo", messageType: String.self, replyType: String.self)
        try anonymousServer.registerRoute(echoRoute) { msg in
            remoteHandlerWasCalled.fulfill()
            return "echo: \(msg)"
        }

        try self.xpcClient.sendMessage("Hello, world!", route: echoRoute) { result in
            XCTAssertNoThrow {
                let response = try result.get()
                XCTAssertEqual(response, "echo: Hello, world!")
            }

            replyBlockWasCalled.fulfill()
        }

        self.waitForExpectations(timeout: 1)
    }

    func testSendWithoutMessageWithReply() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let replyBlockWasCalled = self.expectation(description: "The pong reply was received")

        let pingRoute = XPCRouteWithoutMessageWithReply("ping", replyType: String.self)
        try anonymousServer.registerRoute(pingRoute) {
            remoteHandlerWasCalled.fulfill()
            return "pong"
        }

        try self.xpcClient.send(route: pingRoute) { result in
            XCTAssertNoThrow {
                let response = try result.get()
                XCTAssertEqual(response, "pong")
            }

            replyBlockWasCalled.fulfill()
        }

        self.waitForExpectations(timeout: 1)
    }

    func testSendWithMessageWithoutReply() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")

        let msgNoReplyRoute = XPCRouteWithMessageWithoutReply("msgNoReplyRoute", messageType: String.self)
        try anonymousServer.registerRoute(msgNoReplyRoute) { msg in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }

        try self.xpcClient.sendMessage("Hello, world!", route: msgNoReplyRoute)

        self.waitForExpectations(timeout: 1)
    }

    func testSendWithoutMessageWithoutReply() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")

        let noMsgNoReplyRoute = XPCRouteWithoutMessageWithoutReply("noMsgNoReplyRoute")
        try anonymousServer.registerRoute(noMsgNoReplyRoute) {
            remoteHandlerWasCalled.fulfill()
        }

        try self.xpcClient.send(route: noMsgNoReplyRoute)

        self.waitForExpectations(timeout: 1)
    }
}
