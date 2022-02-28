//
//  Server Error Handler Test.swift
//  
//
//  Created by Josh Kaplan on 2022-02-23.
//

import Foundation
import XCTest
import SecureXPC

// Note: it's intentional this is *not* `Codable` to validate that on the server all `Error`s will be propagated
private enum ExampleError: Error, Equatable {
    case completeAndUtterFailure
}

class ServerErrorHandlerTest: XCTestCase {
    
    func testRegisteredRouteErrorHandler_Sync()  throws {
        let errorToThrow = ExampleError.completeAndUtterFailure
        let errorExpectation = self.expectation(description: "\(errorToThrow) should be provided to error handler")
        
        let failureRoute = XPCRoute.named("always", "throws")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.registerRoute(failureRoute, handler: {
            throw ExampleError.completeAndUtterFailure
        }, errorHandler: { error in
            if error as? ExampleError == errorToThrow {
                errorExpectation.fulfill()
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        })
        
        server.start()
        
        client.send(toRoute: failureRoute, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testRegisteredRouteErrorHandler_Async() throws {
        let errorToThrow = ExampleError.completeAndUtterFailure
        let errorExpectation = self.expectation(description: "\(errorToThrow) should be provided to error handler")
        
        let failureRoute = XPCRoute.named("always", "throws")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.registerRoute(failureRoute, handler: {
            throw ExampleError.completeAndUtterFailure
        }, errorHandler: { (error: Error) async -> Void in
            if error as? ExampleError == errorToThrow {
                errorExpectation.fulfill()
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        })
        
        server.start()
        
        client.send(toRoute: failureRoute, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testGlobalErrorHandler_Sync()  throws {
        let missingPath = ["does", "not", "exist"]
        let errorExpectation = self.expectation(description: "routeNotRegistered([does, not, exist]) is provided")
        
        let missingRoute = XPCRoute.named(missingPath[0], missingPath[1], missingPath[2])
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.setErrorHandler { error in
            switch error {
                case XPCError.routeNotRegistered(let path):
                    if path == missingPath {
                        errorExpectation.fulfill()
                    } else {
                        XCTFail("Unexpected path: \(path)")
                    }
                default:
                    XCTFail("Unexpected error: \(error)")
            }
        }
        server.start()
        
        client.send(to: missingRoute, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testGlobalErrorHandler_Async()  throws {
        let missingPath = ["does", "not", "exist"]
        let errorExpectation = self.expectation(description: "routeNotRegistered([does, not, exist]) is provided")
        
        let missingRoute = XPCRoute.named(missingPath[0], missingPath[1], missingPath[2])
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.setErrorHandler { (error: XPCError) async -> Void in
            switch error {
                case XPCError.routeNotRegistered(let path):
                    if path == missingPath {
                        errorExpectation.fulfill()
                    } else {
                        XCTFail("Unexpected path: \(path)")
                    }
                default:
                    XCTFail("Unexpected error: \(error)")
            }
        }
        server.start()
        
        client.send(toRoute: missingRoute, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testGlobalHandlerDoesNotReceiveRegisteredRouteError_Sync()  throws {
        let errorToThrow = ExampleError.completeAndUtterFailure
        let errorExpectation = self.expectation(description: "\(errorToThrow) should not be provided to error handler")
        errorExpectation.isInverted = true
        
        let failureRoute = XPCRoute.named("always", "throws")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.registerRoute(failureRoute) {
            throw ExampleError.completeAndUtterFailure
        }
        server.setErrorHandler { error in
            errorExpectation.fulfill()
        }
        server.start()
        
        client.send(to: failureRoute, onCompletion: nil)
        
        self.waitForExpectations(timeout: 0.01)
    }
    
    func testGlobalHandlerDoesNotReceiveRegisteredRouteError_Async()  throws {
        let errorToThrow = ExampleError.completeAndUtterFailure
        let errorExpectation = self.expectation(description: "\(errorToThrow) should not be provided to error handler")
        errorExpectation.isInverted = true
        
        let failureRoute = XPCRoute.named("always", "throws")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        server.registerRoute(failureRoute) {
            throw ExampleError.completeAndUtterFailure
        }
        server.setErrorHandler { (error: XPCError) async -> Void in
            errorExpectation.fulfill()
        }
        server.start()
        
        client.send(toRoute: failureRoute, onCompletion: nil)
        
        self.waitForExpectations(timeout: 0.01)
    }
}
