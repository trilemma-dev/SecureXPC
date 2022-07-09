//
//  FileHandleXPCContainer Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-10
//

import Foundation
import XCTest
@testable import SecureXPC

final class FileHandleXPCContainerTests: XCTestCase {
    
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
                            .withReplyType(FileHandleXPCContainer.self)
        server.registerRoute(route) {
            FileHandleXPCContainer(wrappedValue: FileHandle(forReadingAtPath: self.currentPath())!, closeOnEncode: true)
        }
        server.start()
        
        let container = try await client.send(to: route)
        let handle = container.wrappedValue
        defer { try! handle.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: handle.fileDescriptor), currentPath())
    }
    
    struct SecureDocument: Codable {
        var securityLevel: Int
        @FileHandleXPCContainer var document: FileHandle
    }
    
    func testAsPropertyWrapper() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("secure", "document")
                            .withReplyType(SecureDocument.self)
        server.registerRoute(route) {
            SecureDocument(securityLevel: 5, document: FileHandle(forReadingAtPath: self.currentPath())!)
        }
        server.start()
        
        let document = try await client.send(to: route).document
        defer { try! document.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: document.fileDescriptor), currentPath())
    }
}
