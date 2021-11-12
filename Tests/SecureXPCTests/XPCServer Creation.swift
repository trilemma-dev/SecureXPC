//
//  XPCServer Creation.swift
//  
//
//  Created by Josh Kaplan on 2021-11-12
//

import Foundation
import XCTest
import SecureXPC

final class XPCServerCreationTests: XCTestCase {
    
    // Expectation: server can be created without throwing
    func testRetrieveMachServerOnce() throws {
        _ = try XPCServer.forThisMachService(named: "com.example.foo", clientRequirements: [])
    }
    
    // Expectation: same server is successfully returned for the same name and the same requirements
    func testRetrieveMachServerTwiceSameRequirements() throws {
        // These two requirements are semantically equivalent to one another
        var requirement1: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\"" as CFString, [], &requirement1)
        let requirements1 = [requirement1!]
        
        var requirement2: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\" /*exists*/" as CFString, [], &requirement2)
        let requirements2 = [requirement2!]
        
        // The same server instance should be returned each time
        let server1 = try XPCServer.forThisMachService(named: "com.example.bar", clientRequirements: requirements1)
        let server2 = try XPCServer.forThisMachService(named: "com.example.bar", clientRequirements: requirements2)
        
        let server1Pointer = Unmanaged.passUnretained(server1).toOpaque()
        let server2Pointer = Unmanaged.passUnretained(server2).toOpaque()
        XCTAssertEqual(server1Pointer, server2Pointer)
    }
    
    // Expectation: second attempt to get server with same but different requirements throws an error
    func testRetrieveMachServerTwiceDifferentRequirements() throws {
        var requirement: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\"" as CFString, [], &requirement)
        let requirements = [requirement!]
        
        _ = try XPCServer.forThisMachService(named: "com.example.biz", clientRequirements: requirements)

        var otherRequirement: SecRequirement?
        SecRequirementCreateWithString("identifier \"fizz.buzz\"" as CFString, [], &otherRequirement)
        let otherRequirements = [otherRequirement!]
        
        do {
            _ = try XPCServer.forThisMachService(named: "com.example.biz", clientRequirements: otherRequirements)
            XCTFail("No error was thrown. XPCError.conflictingClientRequirements should have been thrown.")
        } catch XPCError.conflictingClientRequirements {
            // Expected behavior
            print("XPC error")
        } catch {
            print("other error")
            XCTFail("Unexpected error thrown. XPCError.conflictingClientRequirements should have been thrown.")
        }
    }
}
