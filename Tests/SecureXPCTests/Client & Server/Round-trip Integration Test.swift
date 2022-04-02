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

        let echoRoute = XPCRoute.named("echo").withMessageType(String.self).withReplyType(String.self)
        anonymousServer.registerRoute(echoRoute) { msg in
            remoteHandlerWasCalled.fulfill()
            return "echo: \(msg)"
        }

        self.xpcClient.sendMessage("Hello, world!", to: echoRoute) { result in
            XCTAssertNoThrow {
                let response = try result.get()
                XCTAssertEqual(response, "echo: Hello, world!")
            }

            replyBlockWasCalled.fulfill()
        }

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithReply_AsyncClient_SyncServer() async throws {
        let echoRoute = XPCRoute.named("echo").withMessageType(String.self).withReplyType(String.self)
        anonymousServer.registerRoute(echoRoute) { msg in "echo: \(msg)" }
        let result = try await xpcClient.sendMessage("Hello, world!", to: echoRoute)
        XCTAssertEqual(result, "echo: Hello, world!")
    }
    
    func testSendWithMessageWithReply_AsyncClient_AsyncServer() async throws {
        let echoRoute = XPCRoute.named("echo").withMessageType(String.self).withReplyType(String.self)
        anonymousServer.registerRoute(echoRoute) { (msg: String) async -> String in
            "echo: \(msg)"
        }
        let result = try await xpcClient.sendMessage("Hello, world!", to: echoRoute)
        XCTAssertEqual(result, "echo: Hello, world!")
    }

    func testSendWithoutMessageWithReply_SyncClient_SyncServer() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let replyBlockWasCalled = self.expectation(description: "The pong reply was received")

        let pingRoute = XPCRoute.named("ping").withReplyType(String.self)
        anonymousServer.registerRoute(pingRoute) {
            remoteHandlerWasCalled.fulfill()
            return "pong"
        }

        self.xpcClient.send(to: pingRoute) { result in
            XCTAssertNoThrow {
                let response = try result.get()
                XCTAssertEqual(response, "pong")
            }

            replyBlockWasCalled.fulfill()
        }

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithReply_AsyncClient_SyncServer() async throws {
        let pingRoute = XPCRoute.named("ping").withReplyType(String.self)
        anonymousServer.registerRoute(pingRoute) { "pong" }
        let result = try await xpcClient.send(to: pingRoute)
        XCTAssertEqual(result, "pong")
    }
    
    func testSendWithoutMessageWithReply_AsyncClient_AsyncServer() async throws {
        let pingRoute = XPCRoute.named("ping").withReplyType(String.self)
        anonymousServer.registerRoute(pingRoute) { () async -> String in
            "pong"
        }
        let result = try await xpcClient.send(to: pingRoute)
        XCTAssertEqual(result, "pong")
    }

    func testSendWithMessageWithoutReply_SyncClient_NilOnCompletion_SyncServer() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")

        let msgNoReplyRoute = XPCRoute.named("msgNoReplyRoute").withMessageType(String.self)
        anonymousServer.registerRoute(msgNoReplyRoute) { msg in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.sendMessage("Hello, world!", to: msgNoReplyRoute, onCompletion: nil)

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithoutReply_SyncClient_OnCompletion_SyncServer() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let responseBlockWasCalled = self.expectation(description: "The response was received")

        let msgNoReplyRoute = XPCRoute.named("msgNoReplyRoute").withMessageType(String.self)
        anonymousServer.registerRoute(msgNoReplyRoute) { msg in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.sendMessage("Hello, world!", to: msgNoReplyRoute) { response in
            responseBlockWasCalled.fulfill()
            XCTAssertNoThrow {
                try response.get()
            }
        }

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithoutReply_AsyncClient_SyncServer() async throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let msgNoReplyRoute = XPCRoute.named("msgNoReplyRoute").withMessageType(String.self)
        anonymousServer.registerRoute(msgNoReplyRoute) { msg in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }
        try await xpcClient.sendMessage("Hello, world!", to: msgNoReplyRoute)
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithoutReply_AsyncClient_AsyncServer() async throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let msgNoReplyRoute = XPCRoute.named("msgNoReplyRoute").withMessageType(String.self)
        anonymousServer.registerRoute(msgNoReplyRoute) { (msg: String) async -> Void in
            XCTAssertEqual(msg, "Hello, world!")
            remoteHandlerWasCalled.fulfill()
        }
        try await xpcClient.sendMessage("Hello, world!", to: msgNoReplyRoute)
        
        await self.waitForExpectations(timeout: 1)
    }

    func testSendWithoutMessageWithoutReply_SyncClient_NilOnCompletion_SyncServer() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")

        let noMsgNoReplyRoute = XPCRoute.named("noMsgNoReplyRoute")
        anonymousServer.registerRoute(noMsgNoReplyRoute) {
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.send(to: noMsgNoReplyRoute, onCompletion: nil)

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithoutReply_SyncClient_OnCompletion_AsyncServer() throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let responseBlockWasCalled = self.expectation(description: "The response was received")

        let noMsgNoReplyRoute = XPCRoute.named("noMsgNoReplyRoute")
        anonymousServer.registerRoute(noMsgNoReplyRoute) {
            remoteHandlerWasCalled.fulfill()
        }

        self.xpcClient.send(to: noMsgNoReplyRoute) { response in
            responseBlockWasCalled.fulfill()
            XCTAssertNoThrow {
                try response.get()
            }
        }

        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithoutReply_AsyncClient_SyncServer() async throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let noMsgNoReplyRoute = XPCRoute.named("noMsgNoReplyRoute")
        anonymousServer.registerRoute(noMsgNoReplyRoute) {
            remoteHandlerWasCalled.fulfill()
        }
        try await xpcClient.send(to: noMsgNoReplyRoute)
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithoutReply_AsyncClient_AsyncServer() async throws {
        let remoteHandlerWasCalled = self.expectation(description: "The remote handler was called")
        let noMsgNoReplyRoute = XPCRoute.named("noMsgNoReplyRoute")
        anonymousServer.registerRoute(noMsgNoReplyRoute, handler: { () async -> Void in
            remoteHandlerWasCalled.fulfill()
        })
        try await xpcClient.send(to: noMsgNoReplyRoute)
        
        await self.waitForExpectations(timeout: 1)
    }
    
    
    func testSendWithoutMessageWithReplySequence_SyncClient_SyncServer() throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        
        let noMessageWithReplySequenceRoute = XPCRoute.named("noMsgWithReplySequence")
                                                      .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        anonymousServer.registerRoute(noMessageWithReplySequenceRoute) { provider in            
            for n in 1...valuesExpected {
                provider.yield(n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finishSuccesfully()
        }
        
        var valuesReceived = 0
        xpcClient.send(to: noMessageWithReplySequenceRoute) { partialResult in
            switch partialResult {
                case .success(_):
                    valuesReceived += 1
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    if valuesExpected == valuesReceived {
                        fullSequenceReceived.fulfill()
                    }
            }
        }
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithReplySequence_AsyncClient_SyncServer() async throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        let noMessageWithReplySequenceRoute = XPCRoute.named("noMsgWithReplySequence")
                                                      .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        anonymousServer.registerRoute(noMessageWithReplySequenceRoute) { provider in
            for n in 1...valuesExpected {
                provider.yield(n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finishSuccesfully()
        }
        
        var valuesReceived = 0
        let sequence = xpcClient.send(to: noMessageWithReplySequenceRoute)
        for try await _ in sequence {
            valuesReceived += 1
        }
        if valuesReceived == valuesExpected {
            fullSequenceReceived.fulfill()
        }
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithoutMessageWithReplySequence_AsyncClient_AsyncServer() async throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        let noMessageWithReplySequenceRoute = XPCRoute.named("noMsgWithReplySequence")
                                                      .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        anonymousServer.registerRoute(noMessageWithReplySequenceRoute) { provider async in
            for n in 1...valuesExpected {
                provider.yield(n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finishSuccesfully()
        }
        
        var valuesReceived = 0
        let sequence = xpcClient.send(to: noMessageWithReplySequenceRoute)
        for try await _ in sequence {
            valuesReceived += 1
        }
        if valuesReceived == valuesExpected {
            fullSequenceReceived.fulfill()
        }
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithReplySequence_SyncClient_SyncServer() throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        
        let messageWithReplySequenceRoute = XPCRoute.named("msgWithReplySequence")
                                                    .withMessageType(Int.self)
                                                    .withSequentialReplyType(Int.self)
        anonymousServer.registerRoute(messageWithReplySequenceRoute) { upperLimit, provider in
            for n in 1...upperLimit {
                provider.yield(n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finishSuccesfully()
        }
        
        let valuesExpected = 5
        var valuesReceived = 0
        xpcClient.sendMessage(valuesExpected, to: messageWithReplySequenceRoute) { partialResult in
            switch partialResult {
                case .success(_):
                    valuesReceived += 1
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    if valuesExpected == valuesReceived {
                        fullSequenceReceived.fulfill()
                    }
            }
        }
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithReplySequence_AsyncClient_SyncServer() async throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        let messageWithReplySequenceRoute = XPCRoute.named("msgWithReplySequence")
                                                    .withMessageType(Int.self)
                                                    .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        var valuesReceived = 0
        anonymousServer.registerRoute(messageWithReplySequenceRoute) { upperLimit, provider in
            for n in 1...upperLimit {
                provider.yield(n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finishSuccesfully()
        }
        
        let sequence = xpcClient.sendMessage(valuesExpected, to: messageWithReplySequenceRoute)
        for try await _ in sequence {
            valuesReceived += 1
        }
        if valuesReceived == valuesExpected {
            fullSequenceReceived.fulfill()
        }
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testSendWithMessageWithReplySequence_AsyncClient_AsyncServer() async throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        let messageWithReplySequenceRoute = XPCRoute.named("msgWithReplySequence")
                                                    .withMessageType(Int.self)
                                                    .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        var valuesReceived = 0
        anonymousServer.registerRoute(messageWithReplySequenceRoute) { upperLimit, provider async in
            for n in 1...upperLimit {
                provider.yield(n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finishSuccesfully()
        }
        
        let sequence = xpcClient.sendMessage(valuesExpected, to: messageWithReplySequenceRoute)
        for try await _ in sequence {
            valuesReceived += 1
        }
        if valuesReceived == valuesExpected {
            fullSequenceReceived.fulfill()
        }
        
        await self.waitForExpectations(timeout: 1)
    }
}
