//
//  SharedRawMemory.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-24
//

import Foundation

/// Uninitialized raw memory shareable across processes.
///
/// > Warning: This class is experimental, changes to it will not be considered breaking for the purposes of SemVer.
/// 
/// ## Topics
/// ### Creation
/// - ``init(size:)``
/// ### Raw Memory
/// - ``rawMemory``
/// - ``size``
/// ### Codable
/// - ``init(from:)``
/// - ``encode(to:)``
public class SharedRawMemory: Codable {
    
    // For the time being it's intentional this error type isn't public as there's no benefit to the end user since
    // there's just one case and it has no associated information they didn't already posses.
    private enum SharedMemoryError: Error {
        case memoryMappingFailed(size: Int)
    }
    
    /// Shared raw memory which can be accessed and modified by multiple processes.
    public let rawMemory: UnsafeMutableRawPointer
    /// The size of ``rawMemory`` in bytes.
    public let size: Int
    /// The XPC representation of the raw memory.
    private let rawMemoryXPCBox: xpc_object_t

    /// Creates unitialized raw shared memory.
    ///
    /// - Parameter size: The size of the shared memory in bytes.
    public init(size: Int) throws {
        self.size = size
        let rawMemory = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, -1, 0)
        guard rawMemory != MAP_FAILED, let rawMemory = rawMemory else {
            throw SharedMemoryError.memoryMappingFailed(size: size)
        }
        self.rawMemory = rawMemory
        self.rawMemoryXPCBox = xpc_shmem_create(rawMemory, size)
    }
    
    deinit {
        munmap(self.rawMemory, self.size)
    }
    
    // MARK: Codable
    
    private enum CodingKeys: String, CodingKey {
        case sharedMemory
        case sharedMemorySize
    }
    
    public func encode(to encoder: Encoder) throws {
        let container = try XPCEncoderImpl.asXPCEncoderImpl(encoder).xpcContainer(keyedBy: CodingKeys.self)
        container.encode(self.rawMemoryXPCBox, forKey: .sharedMemory)
        try container.encode(self.size, forKey: .sharedMemorySize)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try XPCDecoderImpl.asXPCDecoderImpl(decoder).xpcContainer(keyedBy: CodingKeys.self)
        self.rawMemory = try container.decodeSharedMemory(forKey: .sharedMemory)
        self.rawMemoryXPCBox = try container.asSharedMemoryXPCObject(forKey: .sharedMemory)
        self.size = try container.decode(Int.self, forKey: .sharedMemorySize)
    }
}
