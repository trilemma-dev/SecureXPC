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
    
    func testAsyncSequenceInterruptedByServerTermination() async throws {
        // This test is validating that an async sequence will throw an error if the server process exits before the
        // sequence finishes. A request is made to the server to generate the first ten values of the Fibonacci
        // sequence, but once the fifth value (which is 3) is received, a message is sent to the server telling it to
        // terminate.
    
        // This is the _minimum_ set of expected values from the server; however, it's valid for additional values to
        // be received beyond this because the termination request is inherently racing against the server sending the
        // next value in the sequence. (This behavior is intentional to more closely resemble real conditions, not a
        // flaw in the test's design.)
        var expectedValues: [UInt] = [0, 1, 1, 2, 3]
        
        do {
            for try await value in LaunchAgentTests.client.sendMessage(10, to: SharedRoutes.fibonacciRoute) {
                // Already received all of the expected values, but it's still valid to receive more due to racing
                // against process termination
                if expectedValues.isEmpty {
                    continue
                }
                
                XCTAssertEqual(expectedValues.removeFirst(), value)
                if value == 3 {
                    LaunchAgentTests.client.send(to: SharedRoutes.terminate, onCompletion: nil)
                }
            }
            
            XCTFail("No error was thrown when server process exited, \(XPCError.connectionInterrupted) was expected.")
        } catch {
            // Once all of the expected valeus have been received, XPCError.connectionInterrupted error is now expected
            if !expectedValues.isEmpty {
                XCTFail("\(error) received but one or more expected values were not received first: \(expectedValues)")
            }
            else if case XPCError.connectionInterrupted = error {
                // Expected case
            } else {
                XCTFail("Unexpected error \(error) received. \(XPCError.connectionInterrupted) was expected.")
            }
        }
    }
    
    func testAsyncSequenceFullyReceivedBeforeServerTermination() async throws {
        // This test is validating that an async sequence will not be terminated due the server process terminating
        // immediately after it finishes the sequence.
        var expectedValues: [UInt] = [0, 1, 1, 2, 3]
        for try await value in LaunchAgentTests.client.sendMessage(5, to: SharedRoutes.selfTerminatingFibonacciRoute) {
            XCTAssertEqual(expectedValues.removeFirst(), value)
        }
    }
}
