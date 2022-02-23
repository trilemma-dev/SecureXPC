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
    
    func testGetEffectiveUserId_async() async throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        server.registerRoute(route) { () async -> Void in
            // If this fails it'll fatalError, so all we're doing here is ensuring that doesn't happen
            _ = XPCRequestContext.effectiveUserId
        }
        server.start()
        
        try await client.send(route: route)
    }
    
    func testGetEffectiveUserId_sync() throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        let contextValueAccessed = self.expectation(description: "Able to access effective user id")
        
        server.registerRoute(route) {
            // If this fails it'll fatalError, so all we're doing here is ensuring that doesn't happen
            _ = XPCRequestContext.effectiveUserId
            contextValueAccessed.fulfill()
        }
        server.start()
        
        client.send(route: route, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testGetEffectiveGroupId_async() async throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        server.registerRoute(route) { () async -> Void in
            XCTAssertNotNil(XPCRequestContext.effectiveGroupId)
        }
        server.start()
        
        try await client.send(route: route)
    }
    
    func testGetEffectiveGroupId_sync() throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        let contextValueAccessed = self.expectation(description: "Able to access effective group id")
        
        server.registerRoute(route) {
            // If this fails it'll fatalError, so all we're doing here is ensuring that doesn't happen
            _ = XPCRequestContext.effectiveGroupId
            contextValueAccessed.fulfill()
        }
        server.start()
        
        client.send(route: route, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testGetClientCode_async() async throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        server.registerRoute(route) { () async -> Void in
            XCTAssertNotNil(XPCRequestContext.clientCode)
            var staticCode: SecStaticCode?
            SecCodeCopyStaticCode(XPCRequestContext.clientCode!, [], &staticCode)
            var signingInfo: CFDictionary?
            SecCodeCopySigningInformation(staticCode!, [], &signingInfo)
            if let signingInfo = signingInfo as NSDictionary?,
               signingInfo[kSecCodeInfoIdentifier] as? String == "com.apple.xctest" {
                // success
                return
            } else {
                XCTFail("wrong identifier")
            }
        }
        server.start()
        
        try await client.send(route: route)
    }
    
    func testGetClientCode_sync() throws {
        let route = XPCRoute.named("does", "nothing")
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        
        let clientCodeNotNil = self.expectation(description: "Client code should not be nil in this circumstance")
        let xctestIdentifier = self.expectation(description: "Client code's identifier should be com.apple.xctest")
        
        server.registerRoute(route) {
            if let clientCode = XPCRequestContext.clientCode {
                clientCodeNotNil.fulfill()
                var staticCode: SecStaticCode?
                SecCodeCopyStaticCode(clientCode, [], &staticCode)
                var signingInfo: CFDictionary?
                SecCodeCopySigningInformation(staticCode!, [], &signingInfo)
                if let signingInfo = signingInfo as NSDictionary?,
                   signingInfo[kSecCodeInfoIdentifier] as? String == "com.apple.xctest" {
                    xctestIdentifier.fulfill()
                }
            }
            
        }
        server.start()
        
        client.send(route: route, onCompletion: nil)
        
        self.waitForExpectations(timeout: 1)
    }
}
