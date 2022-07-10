//
//  FileDescriptorXPCContainer Tests.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-10
//

import System
import Foundation
import XCTest
import SecureXPC

final class FileDescriptorXPCContainerTests: XCTestCase {
    // MARK: helper functions
    
    private func currentPath(filePath: String = #filePath) -> String { filePath }
    
    private func pathForFileDescriptor(fileDescriptor: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        _ = fcntl(fileDescriptor, F_GETPATH, &buffer)
        
        return String(cString: buffer)
    }
    
    // MARK: FileDescriptor
    
    func testFileDescriptor_DirectInit() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(FileDescriptorForXPC.self)
        server.registerRoute(route) {
            FileDescriptorForXPC(wrappedValue: FileDescriptor(rawValue: open(self.currentPath(), O_RDONLY)))
        }
        server.start()
        
        let container = try await client.send(to: route)
        let descriptor = container.wrappedValue
        defer { try! descriptor.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: descriptor.rawValue), currentPath())
    }
    
    func testFileDescriptor_PropertyWrapper() async throws {
        struct SecureDocument: Codable {
            var securityLevel: Int
            @FileDescriptorForXPC var document: FileDescriptor
        }
        
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
    
    // MARK: FileHandle
    
    func testFileHandle_DirectInit() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(FileHandleForXPC.self)
        server.registerRoute(route) {
            FileHandleForXPC(wrappedValue: FileHandle(forReadingAtPath: self.currentPath())!, closeOnEncode: true)
        }
        server.start()
        
        let container = try await client.send(to: route)
        let handle = container.wrappedValue
        defer { try! handle.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: handle.fileDescriptor), currentPath())
    }
    
    func testFileHandle_PropertyWrapper() async throws {
        struct SecureDocument: Codable {
            var securityLevel: Int
            @FileHandleForXPC var document: FileHandle
        }
        
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
    
    // MARK: Darwin file descriptor
    
    func testDarwinFileDescriptor_DirectInit() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(DarwinFileDescriptorForXPC.self)
        server.registerRoute(route) {
            DarwinFileDescriptorForXPC(wrappedValue: open(self.currentPath(), O_RDONLY))
        }
        server.start()
        
        let container = try await client.send(to: route)
        let descriptor = container.wrappedValue
        defer { close(descriptor) }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: descriptor), currentPath())
    }
    
    func testDarwinFileDescriptor_PropertyWrapper() async throws {
        struct SecureDocument: Codable {
            var securityLevel: Int
            @DarwinFileDescriptorForXPC var document: Int32
        }
        
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("secure", "document")
                            .withReplyType(SecureDocument.self)
        server.registerRoute(route) {
            SecureDocument(securityLevel: 5, document: open(self.currentPath(), O_RDONLY))
        }
        server.start()
        
        let document = try await client.send(to: route).document
        defer { close(document) }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: document), currentPath())
    }
    
    // MARK: Automatic bridging
    
    func testAutomaticBridging_DirectInit() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let serverRoute = XPCRoute.named("fd", "provider")
                                .withReplyType(DarwinFileDescriptorForXPC.self)
        let clientRoute = XPCRoute.named("fd", "provider")
                                .withReplyType(FileDescriptorForXPC.self)
        server.registerRoute(serverRoute) {
            DarwinFileDescriptorForXPC(wrappedValue: open(self.currentPath(), O_RDONLY))
        }
        server.start()
        
        let container = try await client.send(to: clientRoute)
        let descriptor = container.wrappedValue.rawValue
        defer { close(descriptor) }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: descriptor), currentPath())
    }
    
    func testAutomaticBridging_PropertyWrapper() async throws {
        struct ServerSecureDocument: Codable {
            var securityLevel: Int
            @DarwinFileDescriptorForXPC var document: Int32
        }
        
        struct ClientSecureDocument: Codable {
            var securityLevel: Int
            @FileHandleForXPC var document: FileHandle
        }
        
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let serverRoute = XPCRoute.named("secure", "document")
                                .withReplyType(ServerSecureDocument.self)
        let clientRoute = XPCRoute.named("secure", "document")
                                .withReplyType(ClientSecureDocument.self)
        server.registerRoute(serverRoute) {
            ServerSecureDocument(securityLevel: 5, document: open(self.currentPath(), O_RDONLY))
        }
        server.start()
        
        let container = try await client.send(to: clientRoute)
        let descriptor = container.document.fileDescriptor
        defer { close(descriptor) }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: descriptor), currentPath())
    }
}
