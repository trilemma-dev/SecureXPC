//
//  Error Integration Tests.swift
//  
//
//  Created by Josh Kaplan on 2022-02-06.
//

import Foundation
import XCTest
@testable import SecureXPC

private enum ExampleError: Error, Codable, Equatable {
    case twoOfAKind
}

private enum SampleError: Error, Codable {
    case twoOfAKind
}

class ErrorIntegrationTests: XCTestCase {
    
    func testErrorRegistered_Async() async throws {
        let failureRoute = XPCRoute.named("always", "throws")
                                   .throwsType(ExampleError.self)
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.registerRoute(failureRoute) {
            throw ExampleError.twoOfAKind
        }
        server.start()
        
        let errorExpectation = self.expectation(description: "\(ExampleError.twoOfAKind) thrown")

        do {
            try await client.send(route: failureRoute)
            XCTFail("No error thrown")
        } catch ExampleError.twoOfAKind {
            errorExpectation.fulfill()
        } catch {
            XCTFail("Error of wrong type was thrown: \(type(of: error)).\(error.self)")
        }
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testErrorRegistered_Closure() throws {
        let errorToThrow = ExampleError.twoOfAKind
        let failureRoute = XPCRoute.named("always", "throws")
                                   .throwsType(ExampleError.self)
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.registerRoute(failureRoute) {
            throw errorToThrow
        }
        server.start()
        
        let errorExpectation = self.expectation(description: "\(errorToThrow) thrown as underlying error")

        client.send(route: failureRoute) { result in
            do {
                try result.get()
                XCTFail("No errorw thrown")
            } catch XPCError.handlerError(let error) {
                if let underlyingError = error.underlyingError as? ExampleError,
                   underlyingError == errorToThrow {
                    errorExpectation.fulfill()
                } else {
                    XCTFail("Unexpected underlying error: \(error)")
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testOverlappingErrorCasesRegistered_Async() async throws {
        let failureRoute = XPCRoute.named("always", "throws")
                                   .throwsType(ExampleError.self)
                                   .throwsType(SampleError.self)
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.registerRoute(failureRoute) {
            throw ExampleError.twoOfAKind
        }
        server.start()
        
        let errorExpectation = self.expectation(description: "\(ExampleError.twoOfAKind) thrown")

        do {
            try await client.send(route: failureRoute)
            XCTFail("No errorw thrown")
        } catch ExampleError.twoOfAKind {
            errorExpectation.fulfill()
        } catch {
            XCTFail("Unexpected error was thrown: \(type(of: error)).\(error.self)")
        }
        
        await self.waitForExpectations(timeout: 1)
    }
    
    func testErrorNotRegistered_Async() async throws {
        let failureRoute = XPCRoute.named("always", "throws")
                                   .throwsType(SampleError.self)
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.registerRoute(failureRoute) {
            throw ExampleError.twoOfAKind
        }
        server.start()
        
        let errorExpectation = self.expectation(description: "XPCError.handleError thrown")

        do {
            try await client.send(route: failureRoute)
            XCTFail("No errorw thrown")
        } catch XPCError.handlerError(_) {
            errorExpectation.fulfill()
        } catch {
            XCTFail("Unexpected error was thrown: \(type(of: error)).\(error.self)")
        }
        
        await self.waitForExpectations(timeout: 1)
    }
}
