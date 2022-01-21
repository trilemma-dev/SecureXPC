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

    func testSendWithMessageWithReply_SyncClient_SyncServer() throws {
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
    
    func testSendWithMessageWithReply_AsyncClient_SyncServer() async throws {
        let echoRoute = XPCRouteWithMessageWithReply("echo", messageType: String.self, replyType: String.self)
        try anonymousServer.registerRoute(echoRoute) { msg in "echo: \(msg)" }
        let result = try await xpcClient.sendMessage("Hello, world!", route: echoRoute)
        XCTAssertEqual(result, "echo: Hello, world!")
    }
    
    func testSendWithMessageWithReply_AsyncClient_AsyncServer() async throws {
        let echoRoute = XPCRouteWithMessageWithReply("echo", messageType: String.self, replyType: String.self)
        try anonymousServer.registerRoute(echoRoute) { (msg: String) async -> String in
            "echo: \(msg)"
        }
        let result = try await xpcClient.sendMessage("Hello, world!", route: echoRoute)
        XCTAssertEqual(result, "echo: Hello, world!")
    }

    func testSendWithoutMessageWithReply_SyncClient_SyncServer() throws {
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
    
    func testSendWithoutMessageWithReply_AsyncClient_SyncServer() async throws {
        let pingRoute = XPCRouteWithoutMessageWithReply("ping", replyType: String.self)
        try anonymousServer.registerRoute(pingRoute) { "pong" }
        let result = try await xpcClient.send(route: pingRoute)
        XCTAssertEqual(result, "pong")
    }
    
    func testSendWithoutMessageWithReply_AsyncClient_AsyncServer() async throws {
        let pingRoute = XPCRouteWithoutMessageWithReply("ping", replyType: String.self)
        try anonymousServer.registerRoute(pingRoute) { () async -> String in
            "pong"
        }
        let result = try await xpcClient.send(route: pingRoute)
        XCTAssertEqual(result, "pong")
    }

    func testSendWithMessageWithoutReply_SyncClient_NilOnCompletion_SyncServer() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")

        let msgNoReplyRoute = XPCRouteWithMessageWithoutReply("msgNoReplyRoute", messageType: String.self)
        try anonymousServer.registerRoute(msgNoReplyRoute) { msg in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.sendMessage("Hello, world!", route: msgNoReplyRoute, onCompletion: nil)

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithoutReply_SyncClient_OnCompletion_SyncServer() throws {
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
    
    func testSendWithMessageWithoutReply_AsyncClient_SyncServer() async throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let msgNoReplyRoute = XPCRouteWithMessageWithoutReply("msgNoReplyRoute", messageType: String.self)
        try anonymousServer.registerRoute(msgNoReplyRoute) { msg in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }
        try await xpcClient.sendMessage("Hello, world!", route: msgNoReplyRoute)
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithoutReply_AsyncClient_AsyncServer() async throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let msgNoReplyRoute = XPCRouteWithMessageWithoutReply("msgNoReplyRoute", messageType: String.self)
        try anonymousServer.registerRoute(msgNoReplyRoute) { (msg: String) async -> Void in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }
        try await xpcClient.sendMessage("Hello, world!", route: msgNoReplyRoute)
        
        await self.waitForExpectations(timeout: 1)
    }

    func testSendWithoutMessageWithoutReply_SyncClient_NilOnCompletion_SyncServer() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")

        let noMsgNoReplyRoute = XPCRouteWithoutMessageWithoutReply("noMsgNoReplyRoute")
        try anonymousServer.registerRoute(noMsgNoReplyRoute) {
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.send(route: noMsgNoReplyRoute, onCompletion: nil)

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithoutReply_SyncClient_OnCompletion_AsyncServer() throws {
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
    
    func testSendWithoutMessageWithoutReply_AsyncClient_SyncServer() async throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let noMsgNoReplyRoute = XPCRouteWithoutMessageWithoutReply("noMsgNoReplyRoute")
        try anonymousServer.registerRoute(noMsgNoReplyRoute) {
            remoteHandlerWasCalled.fulfill()
        }
        try await xpcClient.send(route: noMsgNoReplyRoute)
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithoutReply_AsyncClient_AsyncServer() async throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let noMsgNoReplyRoute = XPCRouteWithoutMessageWithoutReply("noMsgNoReplyRoute")
        try anonymousServer.registerRoute(noMsgNoReplyRoute, handler: { () async -> Void in
            remoteHandlerWasCalled.fulfill()
        })
        try await xpcClient.send(route: noMsgNoReplyRoute)
        
        await self.waitForExpectations(timeout: 1)
    }
}
