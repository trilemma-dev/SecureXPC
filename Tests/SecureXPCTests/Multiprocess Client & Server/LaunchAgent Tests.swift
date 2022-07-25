//
//  LaunchAgent Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-22
//

import Foundation
import SecureXPC
import XCTest

// By default the set up to run these tests takes a *long* time as it builds an entire launch agent from scratch and
// then loads it. The most time consuming part of this by far is that it builds all of SecureXPC from source.
//
// It is possible to bypass this step and specify the path to your pre-built SecureXPC.o module. If you're using Xcode
// then this will be located at:
//  /Users/<username>/Library/Developer/Xcode/DerivedData/<project>-<random letters>/Build/Products/Debug/SecureXPC.o
//
// Where <project> is the name of the project that you included SecureXPC as a dependency.
//
// On a 16" Intel MacBook Pro, providing a pre-built module reduces set up time from ~25 seconds down to 1 second.
final class LaunchAgentTests: XCTestCase {
    
    static var launchAgent: LaunchAgent!
    static var client: XPCClient!
    
    // Called once before all tests in this class are run
    override class func setUp() {
        super.setUp()
        
        // To provide a pre-built SecureXPC module, specify the URL as the module path
        let modulePath: URL? = nil
        if modulePath == nil {
            print("""
            \(LaunchAgentTests.self) is compiling SecureXPC from source. To speed this up, specify the path to the \
            SecureXPC.o module file in your Xcode DerivedData folder. See code comments for details.
            """)
        }
        launchAgent = try! LaunchAgent.setUp(existingSecureXPCModule: modulePath)
        client = XPCClient.forMachService(named: launchAgent.machServiceName)
    }
    
    // Called once after all tests in this class are run
    override class func tearDown() {
        super.tearDown()
        try! launchAgent.tearDown()
    }
    
    // This test exists primarily to validate that all of the set up actually worked properly
    func testBasicRoundTrip() async throws {
        let message = "Anyone home?"
        let reply = try await LaunchAgentTests.client.sendMessage(message, to: SharedRoutes.echoRoute)
        
        XCTAssertEqual(message, reply)
    }
    
    func testMutateSharedMemory() async throws {
        // This isn't the best example for how shared memory ought to typically be used since it involves explicit XPC
        // calls to actually mutate the shared value, but it's an easy way to test it's working properly
        let reply = try await LaunchAgentTests.client.send(to: SharedRoutes.latestRoute)
        
        let initialNow = try reply.now.retrieveValue()
        let initialValue = try reply.latestValue.retrieveValue()
        
        try await LaunchAgentTests.client.send(to: SharedRoutes.mutateLatestRoute)
        let subsequentNow = try reply.now.retrieveValue()
        let subsequentValue = try reply.latestValue.retrieveValue()
        
        XCTAssertNotEqual(initialNow, subsequentNow)
        XCTAssertNotEqual(initialValue, subsequentValue)
    }
}
