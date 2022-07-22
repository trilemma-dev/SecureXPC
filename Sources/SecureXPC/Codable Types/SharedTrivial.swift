//
//  SharedTrivial.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-21
//

// The internals of how this works are a bit complicated and this complexity is rooted in the fact property wrapper
// initializers can't throw (and that even if they could, that would be rather inconvenient to use in many cases). So
// instead work is delayed until the first time encode(to:) is called since it's not actually needed until then.
// Fundamentally there are two categories of runtime failures: creating a cross-process semaphore (which is used as a
// mutex) and mapping shared memory. These are recoverable errors and so it's inappropriate to use fatalError() to avoid
// this complexity.
//
// Overview of how things work:
// - SharedTrivial<T: Trivial> has a single variable of type SharedState<T> which is an enum that's either in a shared
//   state or not.
//     - It starts in a .notShared state when initialized with a value to wrap.
//     - It starts in a .shared state when deserialized via its Decodable initializer.
//     - It's only valid to go from .notShared -> .shared (this is assumed throughout, but not enforced).
//     - This enum provides the backing storage for the wrapped value via associated properties.
// - When in a not shared state, the wrapped value is stored in a completely standard variable.
// - When in a not shared state, at any time an encode call could happen which would cause a transition to the shared
//   state.
//     - Because of this, a serial dispatch queue is used to ensure that accessing/modifying the wrapped value and
//       encoding can only happen serially.
// - When in a shared state, no serial dispatch queue is used.
//     - Meaning any subsequent encodes do not involve a dispatch queue.
// - When in a shared state, a mutex (in the form of a cross-process semaphore) is used to coordinate
//   access/modification of the wrapped value.
//
// Note: An alternative approach to this was prototyped which was just a "box", not a property wrapper, which eagerly
// threw on initialization. In practice it was much less ergonomic to make use of.

import Foundation

/// Wraps a ``Trivial`` type such that its in-memory representation is shared between processes.
///
/// Use this property wrapper to map the memory for any trivial type into the process on the other side of an XPC connection. This means changes made in one
/// process will be reflected in the other process. Memory can be simultaneously shared across any number of processes, for example a server and two clients.
///
/// This property wrapper may safely be accessed from any thread of any process. Concurrent access or modification is not supported, so accessing or modifying the
/// wrapped value may block the caller.
///
/// >Note: While using this property wrapper makes your type _appear_ to be `Codable`, no actual serialization or deserialization is occurring.
///
/// When creating an ``XPCRoute`` that directly transfers this type as either the message or reply type, `SharedTrivial<T>` must be the specified type, not
/// `T`. This is not applicable when transferring a type which _contains_ `T` as one of its properties.
///
/// ## Topics
/// ### Property Wrapping
/// - ``init(wrappedValue:)``
/// - ``wrappedValue``
/// ### Codable
/// - ``encode(to:)``
/// - ``init(from:)``
@propertyWrapper public class SharedTrivial<T: Trivial>: Codable {
    /// Whether the wrapped value is in shared memory or not. It may start in either state, but may only transition from `.notShared` -> `.shared`.
    private var state: SharedState<T>
    
    /// The wrapped trivial value.
    ///
    /// Only one thread and process at a time can access or modify this value. Blocking will occur if another is doing so when attempting to get or set this value.
    public var wrappedValue: T {
        get {
            switch self.state {
                case .notShared(_, let serialQueue):
                    return serialQueue.sync {
                        // When this code eventually runs, state may now be shared so we need to switch on it again
                        switch self.state {
                            case .notShared(let notShared, _):
                                return notShared.wrappedValue
                            case .shared(let shared):
                                return shared.wrappedValue
                        }
                    }
                case .shared(let shared):
                    return shared.wrappedValue
            }
        }
        set {
            switch self.state {
                case .notShared(_, let serialQueue):
                    serialQueue.sync {
                        // When this code eventually runs, state may now be shared so we need to switch on it again
                        switch self.state {
                            case .notShared(let notShared, _):
                                notShared.wrappedValue = newValue
                            case .shared(let shared):
                                shared.wrappedValue = newValue
                        }
                    }
                case .shared(let shared):
                    shared.wrappedValue = newValue
            }
        }
    }
    
    public init(wrappedValue: T) {
        guard _isPOD(T.self) else {
            fatalError("\(T.self) is not a trivial type")
        }
        
        let serialQueue = DispatchQueue(label: "SharedTrivial<\(T.self)>")
        self.state = .notShared(NotShared<T>(wrappedValue: wrappedValue), serialQueue)
    }
    
    // MARK: Codable
    
    required public init(from decoder: Decoder) throws {
        self.state = .shared(try Shared<T>(from: decoder))
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self.state {
            case .notShared(let notShared, let serialQueue):
                try serialQueue.sync {
                    let shared = try Shared<T>(notSharedState: notShared)
                    try shared.encode(to: encoder)
                    self.state = .shared(shared)
                }
            case .shared(let shared):
                try shared.encode(to: encoder)
        }
    }
}

private enum SharedState<T> {
    case notShared(NotShared<T>, DispatchQueue)
    case shared(Shared<T>)
}

private class NotShared<T> {
    var wrappedValue: T
    
    init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
}

private class Shared<T> {
    /// Mutex used to prevent concurrent access and modification to the wrapped value.
    private var mutex: semaphore_t {
        self.mutexMemory.pointee
    }
    private let mutexMemory: UnsafeMutablePointer<semaphore_t>
    private let mutexMemoryXPCBox: xpc_object_t
    
    /// Mutex guarded access to the wrapped value.
    var wrappedValue: T {
        get {
            semaphore_wait(self.mutex)
            defer { semaphore_signal(self.mutex) }
            return self.wrappedValueMemory.pointee
        }
        set {
            semaphore_wait(self.mutex)
            defer { semaphore_signal(self.mutex) }
            self.wrappedValueMemory.pointee = newValue
        }
    }
    private let wrappedValueMemory: UnsafeMutablePointer<T>
    private let wrappedValueMemoryXPCBox: xpc_object_t
    
    init(notSharedState: NotShared<T>) throws {
        // Create a mutex (using a cross-process semaphore) to coordinate access to the wrapped value's shared memory.
        // For the semaphore to behave like a mutex, the last argument to semaphore_create(...) must be 1.
        var mutex = semaphore_t()
        let result = semaphore_create(mach_task_self_, &mutex, SYNC_POLICY_FIFO, 1)
        guard result == KERN_SUCCESS else {
            let errorMessage: String
            if let machErrorMessage = mach_error_string(result) {
                errorMessage = String(cString: machErrorMessage)
            } else {
                errorMessage = "Error code: \(result)"
            }
            throw SharedTrivialError.mutex(message: errorMessage)
        }
        
        // Both the mutex and the value need to be mapped into shared memory
        (self.mutexMemory, self.mutexMemoryXPCBox) = try share(mutex)
        (self.wrappedValueMemory, self.wrappedValueMemoryXPCBox) = try share(notSharedState.wrappedValue)
    }
    
    deinit {
        munmap(self.wrappedValueMemory, MemoryLayout<T>.stride)
        munmap(self.mutexMemory, MemoryLayout<semaphore_t>.stride)
    }
    
    // MARK: "Codable"
    
    // This class isn't actually Codable because there's no value in being so, but it implements the same function
    // and initializer to make it trivial for SharedTrivial<T: Trivial> which is Codable to delegate all of its coding
    // to this class.
    
    private enum CodingKeys: String, CodingKey {
        case mutex
        case wrappedValue
    }
    
    func encode(to encoder: Encoder) throws {
        let container = try XPCEncoderImpl.asXPCEncoderImpl(encoder).xpcContainer(keyedBy: CodingKeys.self)
        container.encode(self.mutexMemoryXPCBox, forKey: .mutex)
        container.encode(self.wrappedValueMemoryXPCBox, forKey: .wrappedValue)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try XPCDecoderImpl.asXPCDecoderImpl(decoder).xpcContainer(keyedBy: CodingKeys.self)
        self.mutexMemory = try container.decodeSharedMemory(forKey: .mutex)
                                            .bindMemory(to: semaphore_t.self, capacity: 1)
        self.mutexMemoryXPCBox = try container.asSharedMemoryXPCObject(forKey: .mutex)
        self.wrappedValueMemory = try container.decodeSharedMemory(forKey: .wrappedValue)
                                               .bindMemory(to: T.self, capacity: 1)
        self.wrappedValueMemoryXPCBox = try container.asSharedMemoryXPCObject(forKey: .wrappedValue)
    }
}

// Placed outside of the class to avoid its generic constraints
private func share<E>(_ value: E) throws -> (UnsafeMutablePointer<E>, xpc_object_t) {
    let stride = MemoryLayout<E>.stride
    let memory = mmap(nil, stride, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, -1, 0)
    guard memory != MAP_FAILED, let memory = memory else {
        throw SharedTrivialError.mmapFailed(type: E.self, stride: stride)
    }
    let boundMemory = memory.bindMemory(to: E.self, capacity: 1)
    boundMemory.initialize(to: value)
    let xpcMemory = xpc_shmem_create(boundMemory, stride)
    
    return (boundMemory, xpcMemory)
}

// These errors are intentionally not exposed as there's nothing specific an API user could do with this information
// beyond the fact that an error *did* occur.
private enum SharedTrivialError: Error {
    case mmapFailed(type: Any.Type, stride: Int)
    case mutex(message: String)
}
