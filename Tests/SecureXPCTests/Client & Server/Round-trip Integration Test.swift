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
    
    let anonymousServer = XPCServer.makeAnonymous()

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

        self.xpcClient.sendMessage("Hello, world!", route: echoRoute) { result in
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

        self.xpcClient.send(route: pingRoute) { result in
            XCTAssertNoThrow {
                let response = try result.get()
                XCTAssertEqual(response, "pong")
            }

            replyBlockWasCalled.fulfill()
        }

        self.waitForExpectations(timeout: 1)
    }

    func testSendWithMessageWithoutReply_NilOnCompletion() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")

        let msgNoReplyRoute = XPCRouteWithMessageWithoutReply("msgNoReplyRoute", messageType: String.self)
        try anonymousServer.registerRoute(msgNoReplyRoute) { msg in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.sendMessage("Hello, world!", route: msgNoReplyRoute, onCompletion: nil)

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithoutReply_OnCompletion() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let responseBlockWasCalled = self.expectation(description: "The response was received")

        let msgNoReplyRoute = XPCRouteWithMessageWithoutReply("msgNoReplyRoute", messageType: String.self)
        try anonymousServer.registerRoute(msgNoReplyRoute) { msg in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.sendMessage("Hello, world!", route: msgNoReplyRoute) { response in
            responseBlockWasCalled.fulfill()
            XCTAssertNoThrow {
                try response.get()
            }
        }

        self.waitForExpectations(timeout: 1)
    }

    func testSendWithoutMessageWithoutReply_NilOnCompletion() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")

        let noMsgNoReplyRoute = XPCRouteWithoutMessageWithoutReply("noMsgNoReplyRoute")
        try anonymousServer.registerRoute(noMsgNoReplyRoute) {
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.send(route: noMsgNoReplyRoute, onCompletion: nil)

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithoutReply_OnCompletion() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let responseBlockWasCalled = self.expectation(description: "The response was received")

        let noMsgNoReplyRoute = XPCRouteWithoutMessageWithoutReply("noMsgNoReplyRoute")
        try anonymousServer.registerRoute(noMsgNoReplyRoute) {
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.send(route: noMsgNoReplyRoute) { response in
            responseBlockWasCalled.fulfill()
            XCTAssertNoThrow {
                try response.get()
            }
        }

        self.waitForExpectations(timeout: 1)
    }
}
