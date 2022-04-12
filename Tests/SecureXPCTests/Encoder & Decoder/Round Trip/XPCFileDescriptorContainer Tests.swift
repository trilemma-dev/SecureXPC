//
//  XPCFileDescriptorContainer Tests.swift
//  SecurXPC
//
//  Created by Josh Kaplan on 2022-04-12
//

import XCTest
import System
@testable import SecureXPC

final class XPCFileDescriptorContainerTests: XCTestCase {
    
    // MARK: helper functions
    
    func currentPath(filePath: String = #filePath) -> String { filePath }
    
    func pathForFileDescriptor(fileDescriptor: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        _ = fcntl(fileDescriptor, F_GETPATH, &buffer)
        
        return String(cString: buffer)
    }
    
    // MARK: tests
    
    func testNativeFD_NativeFD() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(descriptor: open(self.currentPath(), O_RDONLY), closeDescriptor: true)
        }
        server.start()
        
        let descriptorContainer = try await client.send(to: route)
        let nativeDescriptor = try descriptorContainer.duplicateAsNativeDescriptor()
        defer { close(nativeDescriptor) }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: nativeDescriptor), currentPath())
    }
    
    func testNativeFD_FileHandle() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(descriptor: open(self.currentPath(), O_RDONLY), closeDescriptor: true)
        }
        server.start()
        
        let descriptorContainer = try await client.send(to: route)
        let handle = try descriptorContainer.duplicateAsFileHandle()
        defer { try! handle.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: handle.fileDescriptor), currentPath())
    }
    
    func testNativeFD_FileDescriptor() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(descriptor: open(self.currentPath(), O_RDONLY), closeDescriptor: true)
        }
        server.start()
        
        let descriptorContainer = try await client.send(to: route)
        let descriptor = try descriptorContainer.duplicateAsFileDescriptor()
        defer { try! descriptor.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: descriptor.rawValue), currentPath())
    }
    
    func testFileHandle_NativeFD() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(handle: FileHandle(forReadingAtPath: self.currentPath())!,
                                           closeHandle: true)
        }
        server.start()
        
        let container = try await client.send(to: route)
        let nativeDescriptor = try container.duplicateAsNativeDescriptor()
        defer { close(nativeDescriptor) }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: nativeDescriptor), currentPath())
    }
    
    func testFileHandle_FileHandle() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(handle: FileHandle(forReadingAtPath: self.currentPath())!,
                                           closeHandle: true)
        }
        server.start()
        
        let container = try await client.send(to: route)
        let handle = try container.duplicateAsFileHandle()
        defer { try! handle.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: handle.fileDescriptor), currentPath())
    }
    
    func testFileHandle_FileDescriptor() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(handle: FileHandle(forReadingAtPath: self.currentPath())!,
                                           closeHandle: true)
        }
        server.start()
        
        let container = try await client.send(to: route)
        let descriptor = try container.duplicateAsFileDescriptor()
        defer { try! descriptor.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: descriptor.rawValue), currentPath())
    }
    
    func testFileDescriptor_NativeFD() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(descriptor: FileDescriptor(rawValue: open(self.currentPath(), O_RDONLY)),
                                           closeDescriptor: true)
        }
        server.start()
        
        let container = try await client.send(to: route)
        let nativeDescriptor = try container.duplicateAsNativeDescriptor()
        defer { close(nativeDescriptor) }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: nativeDescriptor), currentPath())
    }
    
    func testFileDescriptor_FileHandle() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(descriptor: FileDescriptor(rawValue: open(self.currentPath(), O_RDONLY)),
                                           closeDescriptor: true)
        }
        server.start()
        
        let container = try await client.send(to: route)
        let handle = try container.duplicateAsFileHandle()
        defer { try! handle.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: handle.fileDescriptor), currentPath())
    }
    
    func testFileDescriptor_FileDescriptor() async throws {
        let server = XPCServer.makeAnonymous()
        let client = XPCClient.forEndpoint(server.endpoint)
        let route = XPCRoute.named("fd", "provider")
                            .withReplyType(XPCFileDescriptorContainer.self)
        server.registerRoute(route) {
            try XPCFileDescriptorContainer(descriptor: FileDescriptor(rawValue: open(self.currentPath(), O_RDONLY)),
                                           closeDescriptor: true)
        }
        server.start()
        
        let container = try await client.send(to: route)
        let descriptor = try container.duplicateAsFileDescriptor()
        defer { try! descriptor.close() }
        
        XCTAssertEqual(pathForFileDescriptor(fileDescriptor: descriptor.rawValue), currentPath())
    }
}

