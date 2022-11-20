//
//  Sequential Result Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-04-05.
//

import XCTest
@testable import SecureXPC

class SequentialResultTests: XCTestCase {
    
    var client: XPCClient! = nil
    let server = XPCServer.makeAnonymous()

    override func setUp() {
        let endpoint = server.endpoint
        client = XPCClient.forEndpoint(endpoint)
        server.start()
    }
    
    // MARK: Basic scenarios
    
    func testSendWithoutMessageWithSequentialReply_SyncClient_SyncServer() throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        
        let noMessageWithReplySequenceRoute = XPCRoute.named("noMsgWithSequentialReply")
                                                      .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        server.registerRoute(noMessageWithReplySequenceRoute) { provider in
            for n in 1...valuesExpected {
                provider.success(value: n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finished()
        }
        
        var valuesReceived = 0
        client.send(to: noMessageWithReplySequenceRoute) { partialResult in
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

    func testSendWithoutMessageWithSequentialReply_AsyncClient_SyncServer() async throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        let noMessageWithReplySequenceRoute = XPCRoute.named("noMsgWithSequentialReply")
                                                      .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        server.registerRoute(noMessageWithReplySequenceRoute) { provider in
            for n in 1...valuesExpected {
                provider.success(value: n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finished()
        }
        
        var valuesReceived = 0
        let sequence = client.send(to: noMessageWithReplySequenceRoute)
        for try await _ in sequence {
            valuesReceived += 1
        }
        if valuesReceived == valuesExpected {
            fullSequenceReceived.fulfill()
        }
        
        await self.waitForExpectations(timeout: 1)
    }

    func testSendWithoutMessageWithSequentialReply_AsyncClient_AsyncServer() async throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        let noMessageWithReplySequenceRoute = XPCRoute.named("noMsgWithSequentialReply")
                                                      .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        server.registerRoute(noMessageWithReplySequenceRoute) { provider async in
            do {
                for n in 1...valuesExpected {
                    try await provider.success(value: n)
                }
                try await provider.finished()
            } catch {
                XCTFail("Unexpected error thrown: \(error)")
            }
            
        }
        
        var valuesReceived = 0
        let sequence = client.send(to: noMessageWithReplySequenceRoute)
        for try await _ in sequence {
            valuesReceived += 1
        }
        if valuesReceived == valuesExpected {
            fullSequenceReceived.fulfill()
        }
        
        await self.waitForExpectations(timeout: 1)
    }

    func testSendWithMessageWithSequentialReply_SyncClient_SyncServer() throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        
        let messageWithReplySequenceRoute = XPCRoute.named("msgWithSequentialReply")
                                                    .withMessageType(Int.self)
                                                    .withSequentialReplyType(Int.self)
        server.registerRoute(messageWithReplySequenceRoute) { upperLimit, provider in
            for n in 1...upperLimit {
                provider.success(value: n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finished()
        }
        
        let valuesExpected = 5
        var valuesReceived = 0
        client.sendMessage(valuesExpected, to: messageWithReplySequenceRoute) { partialResult in
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

    func testSendWithMessageWithSequentialReply_AsyncClient_SyncServer() async throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        let messageWithReplySequenceRoute = XPCRoute.named("msgWithSequentialReply")
                                                    .withMessageType(Int.self)
                                                    .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        var valuesReceived = 0
        server.registerRoute(messageWithReplySequenceRoute) { upperLimit, provider in
            for n in 1...upperLimit {
                provider.success(value: n)
                Thread.sleep(forTimeInterval: 0.01)
            }
            provider.finished()
        }
        
        let sequence = client.sendMessage(valuesExpected, to: messageWithReplySequenceRoute)
        for try await _ in sequence {
            valuesReceived += 1
        }
        if valuesReceived == valuesExpected {
            fullSequenceReceived.fulfill()
        }
        
        await self.waitForExpectations(timeout: 1)
    }

    func testSendWithMessageWithSequentialReply_AsyncClient_AsyncServer() async throws {
        let fullSequenceReceived = self.expectation(description: "The client received the full sequence")
        let messageWithReplySequenceRoute = XPCRoute.named("msgWithSequentialReply")
                                                    .withMessageType(Int.self)
                                                    .withSequentialReplyType(Int.self)
        let valuesExpected = 5
        var valuesReceived = 0
        server.registerRoute(messageWithReplySequenceRoute) { upperLimit, provider async in
            do {
                for n in 1...upperLimit {
                    try await provider.success(value: n)
                }
                try await provider.finished()
            }  catch {
                XCTFail("Unexpected error thrown: \(error)")
            }
        }
        
        let sequence = client.sendMessage(valuesExpected, to: messageWithReplySequenceRoute)
        for try await _ in sequence {
            valuesReceived += 1
        }
        if valuesReceived == valuesExpected {
            fullSequenceReceived.fulfill()
        }
        
        await self.waitForExpectations(timeout: 1)
    }
    
    // MARK: Error generation scenarios
    
    func testPropagateError_Async() async throws {
        let expectation = self.expectation(description: "The third sequence value will throw")
        enum ExampleError: Error, Codable {
            case didNotWork
        }
        
        let route = XPCRoute.named("eventually", "throws")
                            .withSequentialReplyType(Int.self)
                            .throwsType(ExampleError.self)
        
        server.registerRoute(route) { provider in
            provider.success(value: 1)
            provider.success(value: 2)
            provider.failure(error: ExampleError.didNotWork)
        }
        
        let sequence = client.send(to: route)
        var iterator = sequence.makeAsyncIterator()
        
        let first = try await iterator.next()
        XCTAssertEqual(first, 1)
        let second = try await iterator.next()
        XCTAssertEqual(second, 2)
        do {
            _ = try await iterator.next()
        } catch {
            if case ExampleError.didNotWork = error {
                expectation.fulfill()
            }
        }
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testPropagateError_Sync() throws {
        enum ExampleError: Error, Codable {
            case didNotWork
        }
        
        let expectation1 = self.expectation(description: "The first sequence value will be 1")
        let expectation2 = self.expectation(description: "The second sequence value will be 2")
        let expectation3 = self.expectation(description: "The third sequence value will be failure")
        let expectation4 = self.expectation(description: "The fourth sequence value must not be sent")
        expectation4.isInverted = true
        
        var expectations = [(SequentialResult.success(1), expectation1),
                            (SequentialResult.success(2), expectation2),
                            (SequentialResult.failure(XPCError.handlerError(HandlerError(error: ExampleError.didNotWork))), expectation3),
                            (SequentialResult.success(4), expectation4)]
        
        let route = XPCRoute.named("eventually", "throws")
                            .withSequentialReplyType(Int.self)
                            .throwsType(ExampleError.self)
        
        server.registerRoute(route) { provider in
            provider.success(value: 1)
            provider.success(value: 2)
            provider.failure(error: ExampleError.didNotWork)
            provider.success(value: 4)
        }
        
        client.send(to: route) { result in
            let (expectedResult, expectation) = expectations.removeFirst()
            
            switch result {
                case .success(let value):
                    switch expectedResult {
                        case .success(let expectedValue):
                            if value == expectedValue {
                                expectation.fulfill()
                            }
                        default:
                            break
                    }
                case .failure(let error):
                    switch error {
                        case .handlerError(let handlerError):
                            switch handlerError.underlyingError {
                                case .available(let underlyingError):
                                    if case ExampleError.didNotWork = underlyingError {
                                        expectation.fulfill()
                                    }
                                default:
                                    break
                            }
                        default:
                            break
                    }
                case .finished:
                    break
            }
        }
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testDecodeFails_Async() async throws {
        enum MiscContainer: Codable, Equatable {
            case noValue
            case alwaysFailedDecode(NotActuallyDecodable)
        }
        
        struct NotActuallyDecodable: Codable, Equatable {
            enum DecodingIssues: Error {
                case neverDecodes
            }
            
            init() { }
            
            init(from decoder: Decoder) throws {
                throw DecodingIssues.neverDecodes
            }
            
            static func == (lhs: NotActuallyDecodable, rhs: NotActuallyDecodable) -> Bool {
                fatalError()
            }
        }
        
        let expectation = self.expectation(description: "The second sequence value won't be decodable")
        enum ExampleError: Error, Codable {
            case didNotWork
        }
        
        let route = XPCRoute.named("client", "side", "issue")
                            .withSequentialReplyType(MiscContainer.self)
        
        server.registerRoute(route) { provider async in
            do {
                try await provider.success(value: .noValue)
                try await provider.success(value: .alwaysFailedDecode(NotActuallyDecodable()))
                try await provider.success(value: .noValue)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        let sequence = client.send(to: route)
        var iterator = sequence.makeAsyncIterator()
        
        let first = try await iterator.next()
        XCTAssertEqual(first, .noValue)
        do {
            _ = try await iterator.next()
        } catch {
            if case XPCError.decodingError(_) = error {
                expectation.fulfill()
            }
        }
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testSequenceFinished_Async() async throws {
        let expectation = self.expectation(description: "\(XPCError.sequenceFinished) is sent to the error handler")
        
        let route = XPCRoute.named("server", "side", "issue")
                            .withSequentialReplyType(Int.self)
        
        server.registerRoute(route) { provider in
            provider.success(value: 1)
            provider.finished()
            provider.success(value: 2)
        }
        server.setErrorHandler { error in
            switch error {
                case .sequenceFinished:
                    expectation.fulfill()
                default:
                    break
            }
        }
        
        let sequence = client.send(to: route)
        var iterator = sequence.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first, 1)
        let second = try await iterator.next()
        XCTAssertNil(second)
        
        await self.waitForExpectations(timeout: 1)
    }
}
