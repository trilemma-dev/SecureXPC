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
        
        do {
            try await client.send(to: failureRoute)
            XCTFail("No error thrown")
        } catch ExampleError.twoOfAKind {
            // success
        } catch {
            XCTFail("Error of wrong type was thrown: \(type(of: error)).\(error.self)")
        }
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

        client.send(to: failureRoute) { result in
            do {
                try result.get()
                XCTFail("No error thrown")
            } catch XPCError.handlerError(let error) {
                if case let .available(underlyingError) = error.underlyingError,
                   underlyingError as? ExampleError == errorToThrow {
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
        
        do {
            try await client.send(to: failureRoute)
            XCTFail("No error thrown")
        } catch ExampleError.twoOfAKind {
            //success
        } catch {
            XCTFail("Unexpected error was thrown: \(type(of: error)).\(error.self)")
        }
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
        
        do {
            try await client.send(to: failureRoute)
            XCTFail("No error thrown")
        } catch XPCError.handlerError(_) {
            // success
        } catch {
            XCTFail("Unexpected error was thrown: \(type(of: error)).\(error.self)")
        }
    }
}
