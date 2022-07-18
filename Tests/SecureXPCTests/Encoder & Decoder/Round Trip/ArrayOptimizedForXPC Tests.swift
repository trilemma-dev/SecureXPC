//
//  ArrayOptimizedForXPCTests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-19
//

import Foundation
import XCTest
import SecureXPC

final class ArrayOptimizedForXPCTests: XCTestCase {
    struct Info: Codable {
        let description: String
        @ArrayOptimizedForXPC var array: [Int]
    }
    
    func testRoundTrip() async throws {
        let array = [1, 1, 2, 3, 5, 8, 13]
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("one", "info", "please")
                            .withReplyType(Info.self)
        server.registerRoute(route) {
            return Info(description: "This is your info", array: array)
        }
        server.start()
        
        let info = try await client.send(to: route)
        XCTAssertEqual(info.array, array)
    }
}
