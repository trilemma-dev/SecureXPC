//
//  Endpoint Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-07
//

import Foundation
import XCTest
import SecureXPC

class EndpointTests: XCTestCase {
    
    func testTwoClientsFromSameEndpoint() async throws {
        let server = XPCServer.makeAnonymous()
        let client1 = XPCClient.forEndpoint(server.endpoint)
        let client2 = XPCClient.forEndpoint(server.endpoint)
        
        let pingRoute = XPCRoute.named("ping").withReplyType(String.self)
        server.registerRoute(pingRoute) { () async -> String in
            "pong"
        }
        server.start()
        
        let result1 = try await client1.send(to: pingRoute)
        XCTAssertEqual(result1, "pong")
        
        let result2 = try await client2.send(to: pingRoute)
        XCTAssertEqual(result2, "pong")
    }
}
