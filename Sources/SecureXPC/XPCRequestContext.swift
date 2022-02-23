//
//  XPCRequestContext.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-02-22.
//

import Foundation

/// Provides information about the current request being handled by an ``XPCServer``.
///
/// Accessing the properties exposed by this class is a programming error unless called from inside of a closure registered with and called by an `XPCServer`.
///
/// ## Topics
/// ### Client Information
/// - ``clientCode``
/// - ``effectiveUserId``
/// - ``effectiveGroupId``
public class XPCRequestContext {
    private let connection: xpc_connection_t
    private let message: xpc_object_t
    
    private init(connection: xpc_connection_t, message: xpc_object_t) {
        self.connection = connection
        self.message = message
    }
    
    // MARK: task local
        
    @available(macOS 10.15.0, *)
    @TaskLocal
    private static var currentForTask: XPCRequestContext?
    
    @available(macOS 10.15.0, *)
    @discardableResult internal static func setForTask<Success, Failure>(
        connection: xpc_connection_t,
        message: xpc_object_t,
        operation: () throws -> Task<Success, Failure>
    ) rethrows -> Task<Success, Failure> {
        try $currentForTask.withValue(XPCRequestContext(connection: connection, message: message)) {
            try operation()
        }
    }
    
    // MARK: thread local
    
    private static let contextKey = UUID()
    
    @discardableResult internal static func setForCurrentThread<R>(
        connection: xpc_connection_t,
        message: xpc_object_t,
        operation: () throws -> R
    ) rethrows -> R {
        Thread.current.threadDictionary[contextKey] = XPCRequestContext(connection: connection, message: message)
        let result = try operation()
        Thread.current.threadDictionary.removeObject(forKey: contextKey)
        
        return result
    }
    
    // MARK: current context
    
    private static var current: XPCRequestContext {
        if let current = Thread.current.threadDictionary[contextKey] as? XPCRequestContext {
            return current
        } else if #available(macOS 10.15.0, *), let current = currentForTask {
            return current
        } else {
            fatalError("\(XPCRequestContext.self) can only be accessed from within the thread or task of a closure " +
                       "called by \(XPCServer.self).")
        }
    }
    
    // MARK: public functions
    
    // It's intentional that the process id (PID) of the client process is not exposed since misuse of this can
    // readily result in security vulnerabilities
    
    /// The effective user id of the client process.
    public static var effectiveUserId: uid_t {
        xpc_connection_get_euid(current.connection)
    }
    
    /// The effective group id of the client process.
    public static var effectiveGroupId: gid_t {
        xpc_connection_get_egid(current.connection)
    }
    
    /// A represention of the client process.
    public static var clientCode: SecCode? {
        SecCodeCreateWithXPCConnection(current.connection, andMessage: current.message)
    }
}
