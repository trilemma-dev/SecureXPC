//
//  SharedTrivial.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-21
//

// The internals of how this works are a bit complicated and this complexity is rooted in not wanting to have the
// initializer throw as that makes it quite a lot less convenient at the call site. So instead work is delayed until the
// first time encode(to:) is called since it's not actually needed until then. Fundamentally there are two categories of
// runtime failures in order to encode: creating a cross-process semaphore (which is used as a mutex) and mapping shared
// memory. These are recoverable errors and so it's inappropriate to use fatalError() to avoid this complexity.
//
// Overview of how things work:
// - SharedTrivial<T: Trivial> has a single variable of type SharedState<T> which is an enum that's either in a shared
//   state or not.
//     - It starts in a .notShared state when initialized with a value to box.
//     - It starts in a .shared state when deserialized via its Decodable initializer.
//     - It's only valid to go from .notShared -> .shared (this is assumed throughout, but not enforced).
//     - This enum provides the backing storage for the value via associated properties.
// - When in a not shared state, the value is stored in a completely standard variable.
// - When in a not shared state, at any time an encode call could happen which would cause a transition to the shared
//   state.
//     - Because of this, a serial dispatch queue is used to ensure that accessing/modifying the value and encoding can
//       only happen serially.
// - When in a shared state, no serial dispatch queue is used.
//     - Meaning any subsequent encodes do not involve a dispatch queue.
// - When in a shared state, a mutex (in the form of a cross-process semaphore) is used to coordinate
//   access/modification of the value.
//
// Note: An alternative approach to this which was originally implemented was a property wrapper, not a "box", but it
// had to ignore semaphore wait failures in order to conform. Essentially, property wrappers aren't a good fit for
// failable actions like those that are cross-process in nature.

import Foundation

/// Boxes a ``Trivial`` type such that its in-memory representation is shared between processes.
///
/// > Warning: This class is experimental, changes to it will not be considered breaking for the purposes of SemVer.
///
/// Use this class to map the memory for any trivial type into the process on the other side of an XPC connection. This means changes made in one process will be
/// reflected in the other process.
///
/// Instances of this class may safely be accessed from any thread of any process. Concurrent access or modification is not supported, so accessing or updating the
/// value may block the caller.
///
/// ## Implementation Note
/// There is a large range of cross-process data structures which can be built using ``SharedRawMemory`` or ``SharedMemory`` along with a signaling
/// mechanism such as XPC communication and/or a ``SharedSemaphore``. This is perhaps _the_ most basic structure and serves as a proof of concept
/// (although with the expectation it can be used in production apps/services). It was implemented entirely using SecureXPC's public API via ``SharedMemory``
/// and ``SharedSemaphore``.
///
/// ## Topics
/// ### Creation
/// - ``init(_:appGroup:)``
/// ### Value
/// - ``retrieveValue()``
/// - ``updateValue(_:)``
/// ### Codable
/// - ``encode(to:)``
/// - ``init(from:)``
public class SharedTrivial<T: Trivial>: Codable {
    /// Whether the value is in shared memory or not. It may start in either state, but may only transition from `.notShared` -> `.shared`.
    private var state: SharedState<T>
    
    /// Boxes the value such that its in-memory representation can be shared across processes.
    ///
    /// - Parameters:
    ///   - value: The value to be boxed.
    ///   - appGroup: If sandboxed processes are used, the app group must be specified. See
    ///               ``SharedSemaphore/init(initialValue:appGroup:)`` for details.
    public init(_ value: T, appGroup: String? = nil) {
        guard _isPOD(T.self) else {
            fatalError("\(T.self) is not a trivial type")
        }
        
        let serialQueue = DispatchQueue(label: "SharedTrivial<\(T.self)>")
        self.state = .notShared(NotShared<T>(value: value, appGroup: appGroup), serialQueue)
    }
    
    /// Retrieves the boxed value.
    ///
    /// Only one thread and process at a time can retrieve or update this value. Blocking will occur if another is doing so when attempting to retrieve the value.
    public func retrieveValue() throws -> T {
        switch self.state {
            case .notShared(_, let serialQueue):
                return try serialQueue.sync {
                    // When this code eventually runs, state may now be shared so we need to switch on it again
                    switch self.state {
                        case .notShared(let notShared, _):
                            return notShared.value
                        case .shared(let shared):
                            return try shared.retrieveValue()
                    }
                }
            case .shared(let shared):
                return try shared.retrieveValue()
        }
    }
    
    /// Updates the boxed value.
    ///
    /// Only one thread and process at a time can retrieve or update this value. Blocking will occur if another is doing so when attempting to update the value.
    public func updateValue(_ newValue: T) throws {
        switch self.state {
            case .notShared(_, let serialQueue):
                try serialQueue.sync {
                    // When this code eventually runs, state may now be shared so we need to switch on it again
                    switch self.state {
                        case .notShared(let notShared, _):
                            notShared.value = newValue
                        case .shared(let shared):
                            try shared.updateValue(to: newValue)
                    }
                }
            case .shared(let shared):
                try shared.updateValue(to: newValue)
        }
    }
    
    // MARK: Codable
    
    public required init(from decoder: Decoder) throws {
        self.state = .shared(try Shared<T>(from: decoder))
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self.state {
            case .notShared(let notShared, let serialQueue):
                try serialQueue.sync {
                    // This is where the state transitions from .notShared -> .shared
                    let shared = try Shared<T>(notSharedState: notShared)
                    try shared.encode(to: encoder)
                    self.state = .shared(shared)
                }
            case .shared(let shared):
                try shared.encode(to: encoder)
        }
    }
}

private enum SharedState<T: Trivial> {
    case notShared(NotShared<T>, DispatchQueue)
    case shared(Shared<T>)
}

private class NotShared<T: Trivial> {
    var value: T
    let appGroup: String?
    
    init(value: T, appGroup: String?) {
        self.value = value
        self.appGroup = appGroup
    }
}

private class Shared<T: Trivial>: Codable {
    private let sharedMemory: SharedMemory<T>
    private let mutex: SharedSemaphore
    
    func retrieveValue() throws -> T {
        try self.mutex.wait()
        let value = self.sharedMemory.memory.pointee
        self.mutex.post()
        
        return value
    }
    
    func updateValue(to newValue: T) throws {
        try self.mutex.wait()
        self.sharedMemory.memory.pointee = newValue
        self.mutex.post()
    }
    
    init(notSharedState: NotShared<T>) throws {
        self.sharedMemory = try SharedMemory<T>(capacity: 1)
        self.sharedMemory.memory.initialize(to: notSharedState.value)
        
        // By making the semaphore have an initial value of 1 it can be used as a mutex/lock preventing threads (across
        // processes) from simultaneously retrieving or updating the shared memory. This prevents the memory being seen
        // in an inconsistent state since writing new values into memory isn't atomic - for example updating a struct
        // that has multiple integers.
        self.mutex = try SharedSemaphore(initialValue: 1, appGroup: notSharedState.appGroup)
    }
}
