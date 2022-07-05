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
            _ = try XPCServer.forThisProcess(ofType: .xpcService)
            XCTFail("No error was thrown. XPCError.misconfiguredServer should have been thrown.")
        } catch XPCError.misconfiguredServer(_) {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. XPCError.misconfiguredServer should have been thrown.")
        }
    }
    
    func testFailToRetrievedBlessedHelperToolServer() {
        do {
            _ = try XPCServer.forThisProcess(ofType: .blessedHelperTool)
            XCTFail("No error was thrown. XPCError.misconfiguredServer should have been thrown.")
        } catch XPCError.misconfiguredServer(_) {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. XPCError.misconfiguredServer should have been thrown.")
        }
    }
    
    // Expectation: server can be created without throwing
    func testRetrieveMachServerOnce() throws {
        _ = try XPCServer.forThisProcess(ofType: .machService(name: "com.example.foo", requirement: .sameProcess ))
    }
    
    // Expectation: same server is successfully returned for the same name and the same requirements
    func testRetrieveMachServerTwiceSameRequirements() throws {
        // These two requirements are semantically equivalent to one another
        var requirement1: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\"" as CFString, [], &requirement1)
        
        var requirement2: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\" /*exists*/" as CFString, [], &requirement2)
        
        // The same server instance should be returned each time
        let server1 = try XPCServer.forThisProcess(ofType: .machService(name: "com.example.bar",
                                                                        requirement: .secRequirement(requirement1!)))
        let server2 = try XPCServer.forThisProcess(ofType: .machService(name: "com.example.bar",
                                                                        requirement: .secRequirement(requirement2!)))
        XCTAssertIdentical(server1, server2)
    }
    
    // Expectation: second attempt to get server with same but different requirements throws an error
    func testRetrieveMachServerTwiceDifferentRequirements() throws {
        var requirement: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\"" as CFString, [], &requirement)
        
        _ = try XPCServer.forThisProcess(ofType: .machService(name: "com.example.biz",
                                                              requirement: .secRequirement(requirement!)))

        var otherRequirement: SecRequirement?
        SecRequirementCreateWithString("identifier \"fizz.buzz\"" as CFString, [], &otherRequirement)
        
        do {
            _ = try XPCServer.forThisProcess(ofType: .machService(name: "com.example.biz",
                                                                  requirement: .secRequirement(otherRequirement!)))
            XCTFail("No error was thrown. \(XPCError.conflictingClientRequirements) should have been thrown.")
        } catch XPCError.conflictingClientRequirements {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. \(XPCError.conflictingClientRequirements) should have been thrown.")
        }
    }
}
