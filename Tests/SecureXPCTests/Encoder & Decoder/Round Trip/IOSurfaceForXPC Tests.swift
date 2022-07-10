//
//  IOSurfaceForXPC Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-09
//

import IOSurface
import CoreMedia
import XCTest
import System
import SecureXPC

final class IOSurfaceForXPCTests: XCTestCase {
    
    public func testRoundTrip() async throws {
        let surfaceProps: [IOSurfacePropertyKey : Any] = [
            .width: 24,
            .height: 16,
            .pixelFormat: kCMPixelFormat_32BGRA,
            .bytesPerElement: 4
        ]
        
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("surface", "please")
                            .withReplyType(IOSurfaceForXPC.self)
        server.registerRoute(route) {
            IOSurfaceForXPC(wrappedValue: IOSurface(properties: surfaceProps)!)
        }
        server.start()
        
        let surface = try await client.send(to: route).wrappedValue
        
        XCTAssertEqual(surface.width, surfaceProps[.width] as! Int)
        XCTAssertEqual(surface.height, surfaceProps[.height] as! Int)
        XCTAssertEqual(surface.pixelFormat, surfaceProps[.pixelFormat] as! CMPixelFormatType)
        XCTAssertEqual(surface.bytesPerElement, surfaceProps[.bytesPerElement] as! Int)
    }
}
