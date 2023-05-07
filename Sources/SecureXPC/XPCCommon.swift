//
//  XPCCommon.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// A key into the XPC dictionary.
///
/// Instances of this type are part of the "packaging" format used by `Request` and `Response`.
typealias XPCDictionaryKey = UnsafePointer<CChar>

/// A helper function for defining C string constants, intended to have static lifetime.
/// - Parameter input: The input string literal, which will be copied into the result.
/// - Returns: A C string which can be stored indefinitely.
func const(_ input: UnsafePointer<CChar>!) -> UnsafePointer<CChar>! {
	let mutableCopy = strdup(input)!
	return UnsafePointer(mutableCopy) // The result should never actually be mutated
}


/// If this running code is the main executable of an app bundle, the URL to the app bundle will be returned, otherwise the URL to the currently running executable
/// will be returned.
///
/// Some servers (such as `SMAppService` daemons & agents) can be either command line tools (single file executables) or app bundles. Distinguishing between
/// these cases is necessary in order to properly identify a parent app bundle and/or whether one exists.
///
/// See https://github.com/trilemma-dev/SecureXPC/issues/128 for why this is needed.
func currentExecutableOrAppBundleURL() -> URL {
    // To determine if this currently running executable is the main executable for an app bundle:
    // - located in a Contents/MacOS/ directory
    // - parent directory of Contents/MacOS/ directory is for an app bundle
    // - its name matches the CFBundleExecutable info dictionary value
    // Just being in Contents/MacOS/ is insufficient as it's valid for a command line tool to be located there.
    let executablePath = currentExecutableURL()
    if executablePath.deletingLastPathComponent().pathComponents.suffix(2) == ["Contents", "MacOS"],
       executablePath.deletingLastPathComponent()
                     .deletingLastPathComponent()
                     .deletingLastPathComponent().pathExtension == "app",
       executablePath.lastPathComponent == Bundle.main.infoDictionary?["CFBundleExecutable"] as? String {
        return Bundle.main.bundleURL
    } else {
        return executablePath
    }
}

/// The path of the currently running executable.
///
/// This works consistently whether or not the executable is part of a bundle. The returned value is not affected by its location within a bundle (if applicable).
private func currentExecutableURL() -> URL {
    // Adapted from https://developer.apple.com/forums/thread/709577
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    var bufferSize = UInt32(buffer.count)
    let result = _NSGetExecutablePath(&buffer, &bufferSize)
    
    // From _NSGetExecutablePath's documentation:
    //   The function returns 0 if the path was successfully copied, and *bufsize is left unchanged. It returns -1 if
    //   the buffer is not large enough, and *bufsize is set to the size required.
    if result == -1 {
        buffer = [CChar](repeating: 0, count: Int(bufferSize))
        let result2 = _NSGetExecutablePath(&buffer, &bufferSize)
        guard result2 == 0 else {
            fatalError("_NSGetExecutablePath failed (\(result2)) after increasing buffer size to \(bufferSize)")
        }
    } else if result != 0 {
        fatalError("_NSGetExecutablePath failed (\(result)) with undocumented result code")
    }
    
    // From _NSGetExecutablePath's documentation:
    //   Note that _NSGetExecutablePath will return "a path" to the executable not a "real path" to the executable. That
    //   is the path may be a symbolic link and not the real file.
    return URL(fileURLWithFileSystemRepresentation: buffer, isDirectory: false, relativeTo: nil)
        .resolvingSymlinksInPath()
}

/// Creates the static code representation for this running process.
///
/// This is a convenience wrapper around `SecCodeCopySelf` and `SecCodeCopyStaticCode`.
func SecStaticCodeCopySelf() throws -> SecStaticCode {
    var currentCode: SecCode?
    var status = SecCodeCopySelf(SecCSFlags(), &currentCode)
    guard status == errSecSuccess, let currentCode = currentCode else {
        throw XPCError.internalFailure(description: "SecCodeCopySelf failed with status: \(status)")
    }
    
    var currentStaticCode: SecStaticCode?
    status = SecCodeCopyStaticCode(currentCode, SecCSFlags(), &currentStaticCode)
    guard status == errSecSuccess, let currentStaticCode = currentStaticCode else {
        throw XPCError.internalFailure(description: "SecCodeCopyStaticCode failed with status: \(status)")
    }
    
    return currentStaticCode
}

/// Determines the `SecCode` corresponding to an XPC connection and/or message.
///
/// Uses undocumented functionality prior to macOS 11.
func SecCodeCreateWithXPCConnection(_ connection: xpc_connection_t, andMessage message: xpc_object_t) -> SecCode? {
    // Get the code representing the client
    var code: SecCode?
    if #available(macOS 11, *) { // publicly documented, but only available since macOS 11
        SecCodeCreateWithXPCMessage(message, SecCSFlags(), &code)
    } else { // private undocumented function: xpc_connection_get_audit_token, available on prior versions of macOS
        let token = UndocumentedAuditToken.xpc_connection_get_audit_token(connection)
        let tokenValues = [token.val.0, token.val.1, token.val.2, token.val.3,
                           token.val.4, token.val.5, token.val.6, token.val.7]
        let tokenData = Data(bytes: tokenValues, count: tokenValues.count * MemoryLayout<UInt32>.size)
        let attributes = [kSecGuestAttributeAudit : tokenData] as CFDictionary
        SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
    }
    
    return code
}

/// Returns the path for the code instance or `nil` if it could not be determined.
func SecCodeCopyPath(_ code: SecCode) -> URL? {
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
          let staticCode = staticCode else {
        return nil
    }
    
    var path: CFURL?
    guard Security.SecCodeCopyPath(staticCode, SecCSFlags(), &path) == errSecSuccess else {
        return nil
    }
    
    return (path as URL?)?.standardized
}

/// Encapsulates the undocumented function `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
fileprivate struct UndocumentedAuditToken {
    
    /// The function signature of  `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
    private typealias get_audit_token = @convention(c) (xpc_connection_t, UnsafeMutablePointer<audit_token_t>) -> Void
    
    /// Represents the private undocumented function `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
    /// If the function does exist, but does not match the expected signature, then when this variable is loaded the process accessing this variable will crash.
    /// However, this variable should only be access on older versions of macOS which are expected to have a stable non-changing API so this should not occur.
    ///
    /// If this function can't be loaded for some version, a fatalError will intentonally be raised as this should never occur on an older version of macOS supported by
    /// SecureXPC.
    ///
    /// Note that because static variables are implicitly lazy the code to populate this variable is never run unless this variable is accessed.
    private static var xpc_connection_get_audit_tokenFunction: get_audit_token = {
        // From man dlopen 3: If a null pointer is passed in path, dlopen() returns a handle equivalent to RTLD_DEFAULT
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            fatalError("dlopen call to retrieve RTLD_DEFAULT unexpectedly failed, this should never happen")
        }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "xpc_connection_get_audit_token") else {
            // Include macOS version number to assist in reproducing any reported issues
            fatalError("""
            Function xpc_connection_get_audit_token could not be loaded while running on
            \(ProcessInfo.processInfo.operatingSystemVersionString)
            """)
        }
        
        return unsafeBitCast(sym, to: get_audit_token.self)
    }()
    
    /// Wrapper around the private undocumented function `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
    ///
    /// - Parameters:
    ///   - _:  The connection for which the audit token will be retrieved for.
    /// - Returns: The audit token.
    fileprivate static func xpc_connection_get_audit_token(_ connection: xpc_connection_t) -> audit_token_t {
        var token = audit_token_t()
        xpc_connection_get_audit_tokenFunction(connection, &token)
        
        return token
    }
}

/// Determines if this process is sandboxed based on its entitlements.
func isSandboxed() throws -> Bool {
    let entitlementName = "com.apple.security.app-sandbox"
    let entitlement = try readEntitlement(name: entitlementName)
    
    if let entitlement = entitlement {
        guard CFGetTypeID(entitlement) == CFBooleanGetTypeID(), let boolValue = (entitlement as? Bool) else {
            // Under normal circumstances it should not be possible for the entitlement to be anything but a boolean
            // (Maybe it's possible if the app was built outside of Xcode or something unusual like that?)
            fatalError("App sandbox entitlement has a non-boolean value")
        }
        
        return boolValue
    } else { // No entitlement means not sandboxed
        return false
    }
}

/// Represents an app group entitlement or a failure case.
enum AppGroupsEntitlementResult {
    /// The entitlement does not exist.
    case missingEntitlement
    /// The entitlement exists, but is not composed of an array of strings.
    case notArrayOfStrings
    /// The entitlement exists and the associated set contains the app groups.
    ///
    /// The set could be empty.
    case success(Set<String>)
}

/// Retrieves the app group entitlement `com.apple.security.application-groups` for this process.
func readAppGroupsEntitlement() throws -> AppGroupsEntitlementResult {
    guard let entitlement = try readEntitlement(name: "com.apple.security.application-groups") else {
        return .missingEntitlement
    }
    guard CFGetTypeID(entitlement) == CFArrayGetTypeID(), let entitlement = (entitlement as? NSArray) else {
        return .notArrayOfStrings
    }
    var appGroups = Set<String>()
    for element in entitlement {
        guard let elementAsString = element as? String else {
            return .notArrayOfStrings
        }
        appGroups.insert(elementAsString)
    }
    
    return .success(appGroups)
}

/// Reads an entitlement for this process.
func readEntitlement(name: String) throws -> CFTypeRef? {
    guard let task = SecTaskCreateFromSelf(nil) else {
        throw XPCError.internalFailure(description: "SecTaskCreateFromSelf failed")
    }
    
    return SecTaskCopyValueForEntitlement(task, name as CFString, nil)
}

/// The team identifier for this process or `nil` if there isn't one.
func teamIdentifierForThisProcess() throws -> String? {
    var info: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    let status = SecCodeCopySigningInformation(try SecStaticCodeCopySelf(), flags, &info)
    guard status == errSecSuccess, let info = info as NSDictionary? else {
        throw XPCError.internalFailure(description: "SecCodeCopySigningInformation failed with status: \(status)")
    }

    return info[kSecCodeInfoTeamIdentifier] as? String
}

func secRequirementForTeamIdentifier(_ teamIdentifier: String) throws -> SecRequirement {
    // From https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html
    // In regards to subject.OU:
    //     In Apple issued developer certificates, this field contains the developer’s Team Identifier.
    // The "anchor apple generic" portion effectively means the certificate chain was signed by Apple
    let requirementString = """
    anchor apple generic and certificate leaf[subject.OU] = "\(teamIdentifier)"
    """ as CFString
    
    var requirement: SecRequirement?
    guard SecRequirementCreateWithString(requirementString, [], &requirement) == errSecSuccess,
          let requirement = requirement else {
        let message = "Security requirement could not be created; textual representation: \(requirementString)"
        throw XPCError.internalFailure(description: message)
    }
    
    return requirement
}
