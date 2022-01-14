//
//  XPCServer Creation.swift
//  
//
//  Created by Josh Kaplan on 2021-11-12
//

import Foundation
import XCTest
import SecureXPC
@testable import SecureXPC

final class XPCServerCreationTests: XCTestCase {
    
    func testCreateNeverStartedAnonymousServer() {
        // This is testing that the server can succesfully be deallocated without it ever having been started
        // See https://github.com/trilemma-dev/SecureXPC/issues/54
        _ = XPCServer.makeAnonymous()
    }
    
    func testFailToRetrieveServicesServer() {
        do {
            _ = try XPCServer.forThisXPCService()
            XCTFail("No error was thrown. \(XPCError.notXPCService) should have been thrown.")
        } catch XPCError.notXPCService {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. \(XPCError.notXPCService) should have been thrown.")
        }
    }
    
    func testFailToRetrievedBlessedHelperToolServer() {
        do {
            _ = try XPCServer.forThisBlessedHelperTool()
            XCTFail("No error was thrown. XPCError.misconfiguredBlessedHelperTool should have been thrown.")
        } catch XPCError.misconfiguredBlessedHelperTool(_) {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. XPCError.misconfiguredBlessedHelperTool should have been thrown.")
        }
    }
    
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
        XCTAssertIdentical(server1, server2)
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
            XCTFail("No error was thrown. \(XPCError.conflictingClientRequirements) should have been thrown.")
        } catch XPCError.conflictingClientRequirements {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. \(XPCError.conflictingClientRequirements) should have been thrown.")
        }
    }
}
