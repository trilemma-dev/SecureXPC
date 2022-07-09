//
//  FileDescriptorXPCContainer Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-10
//

import System
import Foundation
import XCTest
@testable import SecureXPC

final class FileDescriptorXPCContainerTests: XCTestCase {
    
    // MARK: helper functions
    
    private func currentPath(filePath: String = #filePath) -> String { filePath }
    
    private func pathForFileDescriptor(fileDescriptor: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        _ = fcntl(fileDescriptor, F_GETPATH, &buffer)
        
        return String(cString: buffer)
    }
    
    func testDirectInit() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(FileDescriptorXPCContainer.self)
        server.registerRoute(route) {
            FileDescriptorXPCContainer(wrappedValue: FileDescriptor(rawValue: open(self.currentPath(), O_RDONLY)))
        }
        server.start()
        
        let container = try await client.send(to: route)
        let descriptor = container.wrappedValue
        defer { try! descriptor.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: descriptor.rawValue), currentPath())
    }
    
    struct SecureDocument: Codable {
        var securityLevel: Int
        @FileDescriptorXPCContainer var document: FileDescriptor
    }
    
    func testAsPropertyWrapper() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("secure", "document")
                            .withReplyType(SecureDocument.self)
        server.registerRoute(route) {
            SecureDocument(securityLevel: 5, document: FileDescriptor(rawValue: open(self.currentPath(), O_RDONLY)))
        }
        server.start()
        
        let document = try await client.send(to: route).document
        defer { try! document.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: document.rawValue), currentPath())
    }
}
