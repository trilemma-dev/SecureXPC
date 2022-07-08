//
//  XPCRequestContextTest.swift
//  
//
//  Created by Josh Kaplan on 2022-02-23.
//

import Foundation
import XCTest
import SecureXPC

class XPCRequestContextTest: XCTestCase {
    
    func testGetEffectiveUserID_async() async throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        server.registerRoute(route) { () async -> Void in
            // If this fails it'll fatalError, so all we're doing here is ensuring that doesn't happen
            _ = XPCRequestContext.effectiveUserID
        }
        server.start()
        
        try await client.send(to: route)
    }
    
    func testGetEffectiveUserID_sync() throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        let contextValueAccessed = self.expectation(description: "Able to access effective user id")
        
        server.registerRoute(route) {
            // If this fails it'll fatalError, so all we're doing here is ensuring that doesn't happen
            _ = XPCRequestContext.effectiveUserID
            contextValueAccessed.fulfill()
        }
        server.start()
        
        client.send(to: route, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testGetEffectiveGroupID_async() async throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        server.registerRoute(route) { () async -> Void in
            XCTAssertNotNil(XPCRequestContext.effectiveGroupID)
        }
        server.start()
        
        try await client.send(to: route)
    }
    
    func testGetEffectiveGroupID_sync() throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        let contextValueAccessed = self.expectation(description: "Able to access effective group id")
        
        server.registerRoute(route) {
            // If this fails it'll fatalError, so all we're doing here is ensuring that doesn't happen
            _ = XPCRequestContext.effectiveGroupID
            contextValueAccessed.fulfill()
        }
        server.start()
        
        client.send(to: route, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testGetClientCode_async() async throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        server.registerRoute(route) { () async -> Void in
            XCTAssertNotNil(XPCRequestContext.code)
            var staticCode: SecStaticCode?
            SecCodeCopyStaticCode(XPCRequestContext.code!, [], &staticCode)
            var signingInfo: CFDictionary?
            SecCodeCopySigningInformation(staticCode!, [], &signingInfo)
            XCTAssertEqual((signingInfo! as NSDictionary)[kSecCodeInfoIdentifier] as? String, "com.apple.xctest")
        }
        server.start()
        
        try await client.send(to: route)
    }
    
    func testGetClientCode_sync() throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        let clientCodeNotNil = self.expectation(description: "Client code should not be nil in this circumstance")
        
        server.registerRoute(route) {
            if let clientCode = XPCRequestContext.code {
                clientCodeNotNil.fulfill()
                var staticCode: SecStaticCode?
                SecCodeCopyStaticCode(clientCode, [], &staticCode)
                var signingInfo: CFDictionary?
                SecCodeCopySigningInformation(staticCode!, [], &signingInfo)
                XCTAssertEqual((signingInfo! as NSDictionary)[kSecCodeInfoIdentifier] as? String, "com.apple.xctest")
            }
        }
        server.start()
        
        client.send(to: route, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
}
