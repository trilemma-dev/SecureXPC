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
            XCTFail("No error was thrown. XPCError.misconfiguredServer should have been thrown.")
        } catch XPCError.misconfiguredServer(_) {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. XPCError.misconfiguredServer should have been thrown.")
        }
    }
    
    func testFailToRetrievedBlessedHelperToolServer() {
        do {
            _ = try XPCServer.forMachService(withCriteria: .forBlessedHelperTool())
            XCTFail("No error was thrown. XPCError.misconfiguredServer should have been thrown.")
        } catch XPCError.misconfiguredServer(_) {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. XPCError.misconfiguredServer should have been thrown.")
        }
    }
    
    // Expectation: server can be created without throwing
    func testRetrieveMachServerOnce() throws {
        _ = try XPCServer.forMachService(withCriteria: XPCServer.MachServiceCriteria(machServiceName: "com.example.foo", clientRequirement: .sameProcess ))
    }
    
    // Expectation: same server is successfully returned for the same name and the same requirements
    func testRetrieveMachServerTwiceSameRequirements() throws {
        // These two requirements are semantically equivalent to one another
        var requirement1: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\"" as CFString, [], &requirement1)
        let criteria1 = XPCServer.MachServiceCriteria(machServiceName: "com.example.bar",
                                                      clientRequirement: .secRequirement(requirement1!))
        
        var requirement2: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\" /*exists*/" as CFString, [], &requirement2)
        let criteria2 = XPCServer.MachServiceCriteria(machServiceName: "com.example.bar",
                                                      clientRequirement: .secRequirement(requirement2!))
        
        // The same server instance should be returned each time
        let server1 = try XPCServer.forMachService(withCriteria: criteria1)
        let server2 = try XPCServer.forMachService(withCriteria: criteria2)
        XCTAssertIdentical(server1, server2)
    }
    
    // Expectation: second attempt to get server with same but different requirements throws an error
    func testRetrieveMachServerTwiceDifferentRequirements() throws {
        var requirement: SecRequirement?
        SecRequirementCreateWithString("identifier \"foo.bar\"" as CFString, [], &requirement)
        let criteria = XPCServer.MachServiceCriteria(machServiceName: "com.example.biz",
                                                     clientRequirement: .secRequirement(requirement!))
        
        _ = try XPCServer.forMachService(withCriteria: criteria)

        var otherRequirement: SecRequirement?
        SecRequirementCreateWithString("identifier \"fizz.buzz\"" as CFString, [], &otherRequirement)
        let otherCriteria = XPCServer.MachServiceCriteria(machServiceName: "com.example.biz",
                                                          clientRequirement: .secRequirement(otherRequirement!))
        
        do {
            _ = try XPCServer.forMachService(withCriteria: otherCriteria)
            XCTFail("No error was thrown. \(XPCError.conflictingClientRequirements) should have been thrown.")
        } catch XPCError.conflictingClientRequirements {
            // Expected behavior
        } catch {
            XCTFail("Unexpected error thrown. \(XPCError.conflictingClientRequirements) should have been thrown.")
        }
    }
}
