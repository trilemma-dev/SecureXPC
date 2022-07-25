//
//  SharedMemory.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-24
//

import Foundation

/// Uninitialized typed memory shareable across processes.
///
/// > Warning: This class is experimental, changes to it will not be considered breaking for the purposes of SemVer.
///
/// ## Topics
/// ### Creation
/// - ``init(capacity:)``
/// ### Typed Memory
/// - ``memory``
/// - ``capacity``
/// ### Codable
/// - ``init(from:)``
/// - ``encode(to:)``
public class SharedMemory<T: Trivial>: Codable {
    /// Underlying raw storage which is what is actually encoded/decoded.
    private let rawMemory: SharedRawMemory
    /// Shared typed memory which can be accessed and modified by multiple processes.
    public let memory: UnsafeMutablePointer<T>
    /// The capacity of ``memory``.
    ///
    /// The size of the allocated memory is `capacity * MemoryLayout<T>.stride`.
    public let capacity: Int
    
    /// Creates unitialized typed shared memory.
    ///
    /// - Parameter capacity: The number of instances of `T` which may be stored in this memory.
    public init(capacity: Int) throws {
        self.rawMemory = try SharedRawMemory(size: MemoryLayout<T>.stride * capacity)
        self.capacity = capacity
        self.memory = self.rawMemory.rawMemory.bindMemory(to: T.self, capacity: capacity)
    }
    
    // MARK: Codable
    
    public func encode(to encoder: Encoder) throws {
        try self.rawMemory.encode(to: encoder)
    }
    
    public required init(from decoder: Decoder) throws {
        self.rawMemory = try SharedRawMemory(from: decoder)
        self.capacity = self.rawMemory.size / MemoryLayout<T>.stride
        self.memory = self.rawMemory.rawMemory.bindMemory(to: T.self, capacity: self.capacity)
    }
}
