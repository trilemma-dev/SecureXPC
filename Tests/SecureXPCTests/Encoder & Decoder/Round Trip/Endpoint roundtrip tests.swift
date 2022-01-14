//
//  Endpoint roundtrip tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-01-14
//

import XCTest
@testable import SecureXPC

final class XPCServerEndpointRoundtripTests: XCTestCase {
    func testAnonymousRoundtripStartServerBeforehand() throws {
        let server = XPCServer.makeAnonymous()
        server.start()
        try assertRoundTripEqual(server.endpoint)
    }

    func testAnonymousRoundtripStartServerAfterwards() throws {
        let server = XPCServer.makeAnonymous()
        try assertRoundTripEqual(server.endpoint)
        server.start()
    }
}
