//
//  SharedSemaphore.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-25
//

import Foundation

/// A semaphore shareable across process boundaries.
///
/// > Warning: This class is experimental, changes to it will not be considered breaking for the purposes of SemVer.
///
/// While semaphores can be used in sandboxed app or service, additional configuration is required. See ``init(initialValue:appGroup:)`` for details.
///
/// ## Topics
/// ### Creation
/// - ``init(initialValue:appGroup:)``
/// ### Locking & Unlocking
/// - ``post()``
/// - ``wait()``
/// - ``tryWait()``
/// ### Errors
/// - ``SemaphoreCreationError``
/// - ``SemaphoreWaitError``
/// ### Codable
/// - ``init(from:)``
/// - ``encode(to:)``
public class SharedSemaphore: Codable {
    /// Errors that may prevent successful semaphore creation.
    public enum SemaphoreCreationError: Error {
        /// A signal interrupted semaphore creation.
        case interrupted
        /// The initial value exceeds the maximum supported value.
        case valueExceeedsMaximum
        /// This process has already reached its limit for semaphores or file descriptors in use.
        case processLimitReached
        /// Too many semaphores or file descriptors are open on the system.
        case systemLimitReached
        /// This semaphore can't be decoded because it no longer exists on the system.
        ///
        /// This will occur if the originally created semaphore instance was deinitialized prior to this one being decoded.
        case noLongerExists
        /// There is insufficient space in order to create the semaphore.
        case insufficientSpace
        /// The app group name exceeded the 19 character limit.
        case appGroupNameTooLong
        /// An undocument error occurred.
        case other(Int32)
        
        static func fromErrno() -> SemaphoreCreationError {
            switch errno {
                // From `man sem_open`:
                // [EINTR]   The sem_open() operation was interrupted by a signal.
                case EINTR:  return .interrupted
                // [EINVAL]  The shm_open() operation is not supported; or O_CREAT is specified and value exceeds
                //           SEM_VALUE_MAX.
                // This could happen if the API user provides an initial value exceeding SEM_VALUE_MAX
                case EINVAL: return .valueExceeedsMaximum
                // [EMFILE]  The process has already reached its limit for semaphores or file descriptors in use.
                case EMFILE: return .processLimitReached
                // [ENFILE]  Too many semaphores or file descriptors are open on the system.
                case ENFILE: return .systemLimitReached
                // [ENOENT]  O_CREAT is not set and the named semaphore does not exist.
                // This will happen if the originally created semaphore was deinitialized in one process before decoding
                // occurs in another process.
                case ENOENT: return .noLongerExists
                // [ENOSPC]  O_CREAT is specified, the file does not exist, and there is insufficient space available to
                //           create the semaphore.
                case ENOSPC: return .insufficientSpace
                default:     return .other(errno)
            }
        }
    }
    
    /// The name of the semaphore.
    ///
    /// This is what's actually encoded/decoded.
    private let name: String
    /// The underlying Darwin/POSIX semaphore.
    private let semaphore: Semaphore
    /// If this instance created the semaphore, as opposed to having "retrieved" it.
    ///
    /// This matters when it comes to unlinking the semaphore on `deinit`.
    private let createdSemaphore: Bool
    
    /// Creates a semaphore which may be shared across process boundaries.
    ///
    /// This semaphore may be shared amongst arbitrarily many processes on the system. Once the originally created semaphore has been deinitialized, decoding
    /// of this semaphore will fail, but any semaphore instances already decoded will continue to function.
    ///
    /// ## Sandboxing
    /// Semaphores may be used in sandboxed apps and services, but to do so they must belong to the same application group. To do this, all apps and services
    /// that want to share the same semaphore must have an
    /// [App Groups Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)
    /// and must all have the same application group used to create a semaphore. This is true so long as _any_ of the apps or services are sandboxed, even if
    /// one or more of them is not.
    ///
    /// Internally semaphores must each have a unique name in order to function. This name has a system imposed length limit which is very short and for
    /// sandboxed apps and services the application group must be part of this name. Because of this restriction, you *must* keep the name of your application
    /// group to 19 or fewer characters. On macOS this application group name takes the form of `<team identifier>.<group name>` where
    /// `<team identifier>` is always 10 characters and the `.` is 1 character, thereby leaving 8 characters for `<group name>`.
    ///
    /// - Parameters:
    ///   - initialValue: This semaphore's initial value. To have this semaphore behave like a mutex/lock, pass in a value of 1.
    ///   - appGroup: Required when one or more processes that will be using this semaphore are sandboxed.
    public init(initialValue: UInt32, appGroup: String? = nil) throws {
        self.name = try SharedSemaphore.createName(appGroup: appGroup)
        // This mode allows any user on the system read/write access to the semaphore. We don't want to restrict just
        // the user or group because for example a service may be running as root while an application might be running
        // as a standard user. Since the semaphore itself doesn't expose any data this isn't likely to be an entry point
        // for a security vulnerability, but in theory it could allow another process to be disruptive.
        //
        // Note that while the semaphore names used here are randomly generated, they don't need to be guessed by
        // another process as they can be listed out with: lsof -p <pid> | grep PSXSEM
        let mode: mode_t =  0o666
        guard let semaphore = sem_open(name, O_CREAT | O_EXCL, mode, initialValue), semaphore != SEM_FAILED else {
            switch errno {
                // From `man sem_open`:
                // [EACCES]       The required permissions (for reading and/or writing) are denied for the given flags;
                //                or O_CREAT is specified, the object does not exist, and permission to create the
                //                semaphore is denied.
                // This shouldn't fail because the user has read/write access and sandbox considerations were checked.
                case EACCES:       fatalError("Denied; mode: \(String(mode, radix: 8, uppercase: false))")
                // [ENAMETOOLONG] name exceeded PSEMNAMLEN characters.
                // If this happens the implementation of `createName(...)` is wrong.
                case ENAMETOOLONG: fatalError("Name \(name) (\(name.count)) was too long, PSEMNAMLEN: \(PSEMNAMLEN)")
                // [EEXIST]       O_CREAT and O_EXCL were specified and the semaphore exists.
                // This can happen in theory and the way to properly handle it would be to with some number of retry
                // attempts create a semaphore with a different name. But even in the worst case scenario with an
                // application group name leaving room for only 10 characters, that still allows for ~1 quintillion
                // (64^10) name combinations so this is rather unlikely.
                case EEXIST:       fatalError("Semaphore with \(name) already exists")
                default:           throw SemaphoreCreationError.fromErrno()
            }
        }
        self.semaphore = semaphore
        self.createdSemaphore = true
    }
    
    deinit {
        // If this wasn't called here, it'll be automatically performed when the process terminates - but doing so
        // earlier means more semaphores can be fully deinitialized by the system sooner (so long as they've been
        // unlinked).
        sem_close(self.semaphore)
        
        // Even if all processes that used the semaphore have since closed it (either explicitly or automatically on
        // process exit), the semaphore still exists in the system. Unlinking removes the semaphore once it's count
        // goes to 0; or immediately if the count is already 0.
        //
        // There are two reasonable places sem_unlink could be called, this is one of them and allows the semaphore to
        // be shared with any number of processes. The alternative is to have it called in the decoder init function
        // after sem_open is called, but that won't work properly if more than 2 processes are involved.
        if createdSemaphore {
            sem_unlink(self.name)
        }
    }
    
    // MARK: Codable
    
    public required init(from decoder: Decoder) throws {
        // We don't actually need an XPC decoder to decode a string, but the only situation in which this will be
        // semantically valid is if it's happening via the SecureXPC package as this is a live reference.
        let container = try XPCDecoderImpl.asXPCDecoderImpl(decoder).xpcSingleValueContainer()
        self.name = try container.decode(String.self)
        try SharedSemaphore.checkName(name: name, codingPath: container.codingPath)
        guard let semaphore = sem_open(self.name, 0), semaphore != SEM_FAILED else {
            switch errno {
                // From `man sem_open`:
                // [EACCES]       The required permissions (for reading and/or writing) are denied for the given flags;
                //                or O_CREAT is specified, the object does not exist, and permission to create the
                //                semaphore is denied.
                // Since the original permissions level was user, group, and world read/write this ought not to be
                // possible, but possibly sort of unaccounted for sandboxing issue might also be able to cause this?
                case EACCES:       fatalError("Unable to create semaphore due to access permission level")
                // [ENAMETOOLONG] name exceeded PSEMNAMLEN characters.
                // This shouldn't be possible as in order to be decoding with this name, a semaphore with this name
                // should already have been successfully created.
                case ENAMETOOLONG: fatalError("Name \(name) (\(name.count)) was too long, PSEMNAMLEN: \(PSEMNAMLEN)")
                // [EEXIST]       O_CREAT and O_EXCL were specified and the semaphore exists.
                // This should not be possible as neither of these flags were provided.
                case EEXIST:       fatalError("EEXIST should not be possible")
                default:
                    let debugDescription = "Shared semaphore could not be decoded, see underlying error"
                    let context = DecodingError.Context(codingPath: container.codingPath,
                                                        debugDescription: debugDescription,
                                                        underlyingError: SemaphoreCreationError.fromErrno())
                    throw DecodingError.dataCorrupted(context)
            }
        }
        self.semaphore = semaphore
        self.createdSemaphore = false
    }
    
    public func encode(to encoder: Encoder) throws {
        // While we don't need an XPC encoder to encode a string, this semaphore name doesn't mean anything in a durable
        // serializable way; it's effectively a live reference.
        let container = try XPCEncoderImpl.asXPCEncoderImpl(encoder).xpcSingleValueContainer()
        container.encode(self.name)
    }
    
    // MARK: Name helpers
    
    private static func createName(appGroup: String?) throws -> String {
        // Most of this function isn't actually creating a name, it's validating a name _can_ be created based on
        // whether this process is sandboxed and/or an app group was provided.
        
        if try isSandboxed() {
            guard appGroup != nil else {
                fatalError("This process is sandboxed, an app group must be provided")
            }
        }
        
        // The name of the semaphore must be less than PSEMNAMLEN (which in practice appears to be 31) or creation fails
        let name: String
        if let appGroup = appGroup {
            // If the user provided an app group, ensure it's present in the app groups entitlement otherwise it won't
            // actually work. Note: It's perfectly valid to provide an app group when not sandboxed, for example because
            // the other process(es) are sandboxed.
            switch try readApplicationGroupsEntitlement() {
                case .missingEntitlement:
                    fatalError("""
                    App groups entitlement com.apple.security.application-groups is missing, but must be present \
                    because the app group \(appGroup) was provided.
                    """)
                case .notArrayOfStrings:
                    fatalError("""
                    App groups entitlement com.apple.security.application-groups is not an array of strings.
                    """)
                case .success(let appGroups):
                    guard appGroups.contains(appGroup) else {
                        fatalError("""
                        The provided app group is not an entry in the com.apple.security.application-groups \
                        entitlement array of strings. App groups:
                        \(appGroups.joined(separator: "\n"))
                        """)
                    }
            }
            
            // Self-imposed requirement to leave room for add a randomly generated shortcode
            guard appGroup.count <= 19 else {
                throw SemaphoreCreationError.appGroupNameTooLong
            }
            
            // From https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AppSandboxInDepth/AppSandboxInDepth.html#//apple_ref/doc/uid/TP40011183-CH3-SW24
            //     POSIX semaphores and shared memory names must begin with the application group identifier, followed
            //     by a slash (/), followed by a name of your choosing.
            let codeLength = Int(PSEMNAMLEN) - 2 - appGroup.count
            name = appGroup + "/" + ShortCodeGenerator.generateCode(ofLength: codeLength)
        } else {
            name = ShortCodeGenerator.generateCode(ofLength: Int(PSEMNAMLEN) - 1)
        }
        
        return name
    }
    
    /// Checks that the name for the semaphore is usable by a sandboxed process.
    ///
    /// If this isn't sandboxed process, no checks are necessary nor performed.
    private static func checkName(name: String, codingPath: [CodingKey]) throws {
        // If this process isn't sandboxed, then any decoded name is fine
        guard try isSandboxed() else {
            return
        }
        
        // Otherwise we need to check the name contains an app group which is present in this processes's
        // com.apple.security.application-groups entitlement. If this isn't done then sem_open will fail with a rather
        // cryptic and unhelpful error code.
        var debugDescription: String?
        switch try readApplicationGroupsEntitlement() {
            case .missingEntitlement:
                debugDescription = """
                In order for a sandboxed process to receive a semaphore it must belong to one or more app groups as \
                specified in its com.apple.security.application-groups entitlement.
                """
            case .notArrayOfStrings:
                debugDescription = """
                App groups entitlement com.apple.security.application-groups is not an array of strings.
                """
            case .success(let appGroups):
                // The name created by `createName(applicationGroupName:)` is in the form of:
                //   <team identifier>.<group name>/<random ordering of 0-9, a-z, A-Z, . and _>
                if name.contains("/"), let appGroup = name.split(separator: "/").first {
                    if !appGroups.contains(String(appGroup)) {
                        debugDescription = """
                        This semaphore was created with an app group which this process does not have in its \
                        com.apple.security.application-groups entitlement. \n
                        App group name used to create semaphore: \(appGroup)
                        App group names:
                        \(appGroups.joined(separator: "\n"))
                        """
                    }
                } else {
                    debugDescription = """
                    Because this is a sandboxed process, the received semaphore must be created with an app group; \
                    however, one was not provided when it was initially created.
                    """
                }
        }
        if let debugDescription = debugDescription {
            let context = DecodingError.Context(codingPath: codingPath,
                                                debugDescription: debugDescription,
                                                underlyingError: nil)
            throw DecodingError.dataCorrupted(context)
        }
    }
    
    // MARK: Functions
    
    /// Unlocks the semaphore.
    ///
    /// The value of this semaphore is incremented, and all threads which are waiting on this semaphore are awakened.
    public func post() {
        // According to its man page the only reason a sem_post call can fail is if the semaphore passed in isn't valid.
        // If that occurs, that's an implementation error in this file so we should fail loudly.
        guard sem_post(self.semaphore) == 0 else {
            fatalError("sem_post unexpectedly failed with code: \(errno)")
        }
    }
    
    /// Errors that may occur when calling ``wait()`` and ``tryWait()``.
    public enum SemaphoreWaitError: Error {
        /// A deadlock was detected.
        case deadlock
        /// Waiting was interrupted by a signal.
        case interrupted
        /// An undocument error occurred.
        case other(Int32)
        
        static func fromErrno() -> SemaphoreWaitError {
            switch errno {
                // Documentation from `man sem_wait`
                // [EDEADLK] A deadlock was detected.
                case EDEADLK: return .deadlock
                // [EINTR]   The call was interrupted by a signal.
                case EINTR:   return .interrupted
                // [EINVAL]  sem is not a valid semaphore descriptor.
                // This should never be possible unless there's a bug in this implementation. Even if the original
                // creator of the semaphore calls sem_unlink the semaphore still remains valid until there are no more
                // instances of it in any process.
                case EINVAL:  fatalError("sem_wait was provided an invalid semaphore descriptor")
                // [EAGAIN] The semaphore is already locked.
                // This isn't actually an "error" and so is handled by `tryWait()` separately.
                default:      return SemaphoreWaitError.other(errno)
            }
        }
    }
    
    /// Locks the semaphore.
    ///
    /// When calling this function if this semaphore's value is zero, the calling thread will block until the lock is acquired or until the call is interrupted by a signal.
    public func wait() throws {
        guard sem_wait(self.semaphore) == 0 else {
            throw SemaphoreWaitError.fromErrno()
        }
    }
    
    /// Locks the semaphore only if no blocking is required.
    ///
    /// When calling this function if the semaphore is already locked, this function will not change the state of the semaphore and will immediately return `false`.
    ///
    /// - Returns: `true` if the lock was acquired, `false` otherwise meaning the state of this semaphore was not changed.
    public func tryWait() throws -> Bool {
        guard sem_trywait(self.semaphore) == 0 else {
            if errno == EAGAIN {
                return false
            }
            throw SemaphoreWaitError.fromErrno()
        }
        
        return true
    }
}

/// Generates random shortcodes of a specified length.
fileprivate struct ShortCodeGenerator {
    private init() { }
    
    /// Characters which are valid in a POSIX path.
    ///
    /// There are 64 of them which is rather nice by making it base64, but that's not a requirement.
    private static let characters = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "_",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
    ]

    fileprivate static func generateCode(ofLength length: Int) -> String {
        var code = ""
        for _ in 0..<length {
            let randomIndex = Int(arc4random_uniform(UInt32(characters.count)))
            code.append(characters[randomIndex])
        }
        return code
    }
}
