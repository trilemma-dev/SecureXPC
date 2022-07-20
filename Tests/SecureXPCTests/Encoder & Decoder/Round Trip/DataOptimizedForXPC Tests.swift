//
//  DataOptimizedForXPCTests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-19
//

import Foundation
import XCTest
import SecureXPC

final class DataOptimizedForXPCTests: XCTestCase {
    struct Info: Codable {
        let description: String
        @DataOptimizedForXPC var data: Data
    }
    
    func testRoundTrip() async throws {
        let data = Data(base64Encoded: "QWxsIHlvdXIgYmFzZSBhcmUgYmVsb25nIHRvIHVz")!
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("one", "info", "please")
                            .withReplyType(Info.self)
        server.registerRoute(route) {
            return Info(description: "This is your info", data: data)
        }
        server.start()
        
        let info = try await client.send(to: route)
        XCTAssertEqual(info.data, data)
    }
}
