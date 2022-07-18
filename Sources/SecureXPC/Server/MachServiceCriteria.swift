//
//  MachServiceCriteria.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-17
//

import Foundation

public extension XPCServer {
    /// The criteria used to retrieve an ``XPCServer`` via ``XPCServer/forMachService(withCriteria:)``.
    ///
    /// Use this struct to:
    /// - create requirements for a Mach service without built-in support
    /// - specify the name of the Mach service when this process offers multiple Mach services
    /// - customize the client requirement for a type with built-in support 
    ///
    /// It's always preferable when built-in support for a type exists to use the corresponding factory function such as
    ///  ``forBlessedHelperTool(named:withClientRequirement:)`` because it will ensure the calling process actually *is* a blessed helper tool
    /// and if a name is provided that the name is one of the Mach services listed in its launchd property list. This can be helpful in resolving configuration issues
    /// and for quickly finding typos. This is also convenient when specifying the name of a Mach service because there are multiple offered and want to use the
    /// default client requirement.
    ///
    /// ## Topics
    /// ### Explicit Configuration
    /// - ``init(machServiceName:clientRequirement:)``
    /// ### Factory Functions
    /// - ``forBlessedHelperTool(named:withClientRequirement:)``
    /// - ``forDaemon(named:withClientRequirement:)``
    /// - ``forAgent(named:withClientRequirement:)``
    /// - ``forLoginItem(withClientRequirement:)``
    struct MachServiceCriteria {
        /// The name of the Mach service to be retrieved.
        internal let machServiceName: String
        /// The requirement for clients in order to be allowed to communicate with this Mach service.
        internal let clientRequirement: XPCClientRequirement
        
        /// Explicitly specified criteria for a Mach service.
        ///
        /// - Parameters:
        ///   - machServiceName: The name of the service to be retrieved; no validation is performed.
        ///   - clientRequirement: The requirement for clients in order to be allowed to communicate with this Mach service.
        public init(machServiceName: String, clientRequirement: XPCClientRequirement) {
            self.machServiceName = machServiceName
            self.clientRequirement = clientRequirement
        }
        
        /// Criteria for this process, automatically configured.
        ///
        /// Auto-configuration currently supports the following when exactly one unique `MachServices` entry is present:
        /// - ``forBlessedHelperTool(named:withClientRequirement:)``
        /// - ``forAgent(named:withClientRequirement:)``
        /// - ``forDaemon(named:withClientRequirement:)``
        ///
        /// Addtionally ``forLoginItem(withClientRequirement:)`` can always be auto-configured.
        ///
        /// When auto configuration is not possible, criteria can be explicitly specified via ``init(machServiceName:clientRequirement:)``.
        internal static func autoConfigure() throws -> MachServiceCriteria {
            if validateThisProcessIsABlessedHelperTool().didSucceed {
                return try _forBlessedHelperTool()
            } else if validateThisProcessIsALoginItem().didSucceed {
                return try _forLoginItem()
            } else if validateThisProcessIsAnSMAppServiceDaemon().didSucceed {
                return try _forDaemon()
            } else if validateThisProcessIsAnSMAppServiceAgent().didSucceed {
                return try _forAgent()
            } else {
                throw XPCError.misconfiguredServer(description: """
                Unable to determine what type of process this Mach service belongs to. Criteria will need to be \
                explicitly provided.
                """)
            }
        }
        
        // Common logic used by blessed helper tool, agent, & daemon
        private static func createCriteria(
            named name: String?,
            machServices: Set<String>,
            withClientRequirement requirement: XPCClientRequirement?,
            defaultClientRequirementCreator: () throws -> XPCClientRequirement
        ) throws -> MachServiceCriteria {
            let machServiceName: String
            if let name = name {
                guard machServices.contains(name) else {
                    throw XPCError.misconfiguredServer(description: """
                    There is no MachServices key for value: \(name)
                    Available keys:
                    \(machServices.joined(separator: "\n"))
                    """)
                }
                machServiceName = name
            } else {
                guard machServices.count == 1, let inferredName = machServices.first else {
                    throw XPCError.misconfiguredServer(description: """
                    In order to not provide a name, the MachServices dictionary must have exactly one entry. Entries
                    present:
                    \(machServices.joined(separator: "\n"))
                    """)
                }
                machServiceName = inferredName
            }
            
            let clientRequirement = try requirement ?? defaultClientRequirementCreator()
            
            return MachServiceCriteria(machServiceName: machServiceName, clientRequirement: clientRequirement)
        }
        
        /// Criteria for a helper tool installed with
        /// [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless).
        ///
        /// - Parameters:
        ///   - name: The name of the Mach service to be created. If there is exactly one `MachServices` entry in the embedded launchd property list then
        ///           the name does not need to be provided and can be automatically inferred.
        ///   - requirement: The requirement for the client. If no requirement is provided this will be automatically generated using the [`SMAuthorizedClients`](https://developer.apple.com/documentation/bundleresources/information_property_list/smauthorizedclients)
        ///                  array in the embedded info property list. Each element in the array must be a valid security requirement, meaning it must be
        ///                  creatable by
        ///     [`SecRequirementCreateWithString`](https://developer.apple.com/documentation/security/1394522-secrequirementcreatewithstring).
        ///                  The resulting client requirement accept incoming requests from clients that meet _any_ of the `SMAuthorizedClients`
        ///                  requirements.
        /// - Returns: Criteria for a Mach service belonging to a helper tool installed with `SMJobBless`.
        public static func forBlessedHelperTool(
            named name: String? = nil,
            withClientRequirement requirement: XPCClientRequirement? = nil
        ) throws -> MachServiceCriteria {
            try validateThisProcessIsABlessedHelperTool().throwIfFailure()
            
            return try _forBlessedHelperTool(named: name, withClientRequirement: requirement)
        }
        
        private static func _forBlessedHelperTool(
            named name: String? = nil,
            withClientRequirement requirement: XPCClientRequirement? = nil
        ) throws -> MachServiceCriteria {
            try createCriteria(named: name,
                               machServices: try blessedHelperToolMachServices(),
                               withClientRequirement: requirement,
                               defaultClientRequirementCreator: blessedHelperToolClientRequirements)
        }
        
        /// Criteria for a launch daemon registered via
        /// [`SMAppService.daemon(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/3945410-daemon).
        ///
        /// This does **not** include launch daemons manually registered via a property list in `/Library/LaunchDaemons/`.
        ///
        /// - Parameters:
        ///   - name: The name of the Mach service to be created. If there is exactly one `MachServices` entry across all bundled property lists which
        ///           reference the `BundleProgram` corresponding to this executable then the name does not need to be provided and can be
        ///           automatically inferred.
        ///   - requirement: The requirement for the client. If no requirement is provided, one will be automatically generated to meet the designated
        ///                  requirement of the containing app (meaning in most cases only the containing app's requests will be accepted).
        /// - Returns: Criteria for a Mach service belonging to a daemon registered via `SMAppService.daemon(plistName:)`.
        @available(macOS 13.0, *)
        public static func forDaemon(
            named name: String? = nil,
            withClientRequirement requirement: XPCClientRequirement? = nil
        ) throws -> MachServiceCriteria {
            try validateThisProcessIsAnSMAppServiceDaemon().throwIfFailure()
            
            return try _forDaemon(named: name, withClientRequirement: requirement)
        }
        
        private static func _forDaemon(
            named name: String? = nil,
            withClientRequirement requirement: XPCClientRequirement? = nil
        ) throws -> MachServiceCriteria {
            try createCriteria(named: name,
                               machServices: try agentOrDaemonMachServices(directory: .daemon),
                               withClientRequirement: requirement) {
                // Use the parent's designated requirement as the client criteria. Considering the considerable
                // privilege escalation potential this intentionally takes a more restricted approach than what is taken
                // for a login item or agent.
                try .parentDesignatedRequirement
            }
        }
        
        /// Criteria for a launch agent registered via
        /// [`SMAppService.agent(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/3945409-agent).
        ///
        /// This does **not** include launch agent manually registered via a property list in `~/Library/LaunchAgents` or
        /// `/Library/LaunchAgents`.
        ///
        /// - Parameters:
        ///   - name: The name of the Mach service to be created. If there is exactly one `MachServices` entry across all bundled property lists which
        ///           reference the `BundleProgram` corresponding to this executable then the name does not need to be provided and can be
        ///           automatically inferred.
        ///   - requirement: The requirement for the client.  If none is provided then clients will be trusted if they have the same team identifier as
        ///                  this agent; if this agent has no team identifier an error will be thrown.
        /// - Returns: Criteria for a Mach service belonging to a daemon registered via `SMAppService.agent(plistName:)`.
        @available(macOS 13.0, *)
        public static func forAgent(
            named name: String? = nil,
            withClientRequirement requirement: XPCClientRequirement? = nil
        ) throws -> MachServiceCriteria {
            try validateThisProcessIsAnSMAppServiceDaemon().throwIfFailure()
            
            return try _forAgent(named: name, withClientRequirement: requirement)
        }
        
        private static func _forAgent(
            named name: String? = nil,
            withClientRequirement requirement: XPCClientRequirement? = nil
        ) throws -> MachServiceCriteria {
            try createCriteria(named: name,
                               machServices: try agentOrDaemonMachServices(directory: .agent),
                               withClientRequirement: requirement) {
                // Use the team identifier as the client criteria. An alternative approach would be to use the parent's
                // designated requirement or restrict to within the parent's app bundle, but if either of those were the
                // desired use case for this launch agent then in most cases an XPC service would be a better fit. If a
                // launch agent is being used it's reasonable to default to allowing requests from outside of the app
                // bundle as long as it's from the same team identifier.
                try .sameTeamIdentifier
            }
        }
        
        /// Criteria for a login item enabled with
        /// [`SMLoginItemSetEnabled`](https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled).
        ///
        /// If this is a sandboxed login item, the
        ///     [`com.apple.security.application-groups`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)
        /// entitlement must be present and one of the application groups must have the same team identifier as this login item.
        ///
        /// - Parameter requirement: The requirement for the client. If none is provided then clients will be trusted if they have the same team identifier as
        ///                          this login item (if this login item has a team identifier) and belong to the same parent app bundle.
        /// - Returns: Criteria for a Mach service belonging to a login item enabled with `SMLoginItemSetEnabled`.
        public static func forLoginItem(
            withClientRequirement requirement: XPCClientRequirement? = nil
        ) throws -> MachServiceCriteria {
            try validateThisProcessIsALoginItem().throwIfFailure()
            
            return try _forLoginItem(withClientRequirement: requirement)
        }
        
        private static func _forLoginItem(
            withClientRequirement requirement: XPCClientRequirement? = nil
        ) throws -> MachServiceCriteria {
            try throwIfSandboxedAndThisLoginItemCannotCommunicateOverXPC()
            
            // From Apple's AppSandboxLoginItemXPCDemo:
            // https://developer.apple.com/library/archive/samplecode/AppSandboxLoginItemXPCDemo/
            //     LaunchServices implicitly registers a Mach service for the login item whose name is the same as the
            //     login item's bundle identifier.
            guard let bundleID = Bundle.main.bundleIdentifier else {
                throw XPCError.misconfiguredServer(description: """
                Login items must have a bundle identifier (CFBundleIdentifier).
                """)
            }
            
            let clientRequirement: XPCClientRequirement
            if let requirement = requirement {
                clientRequirement = requirement
            } else {
                if let sameTeamRequirement = try? XPCClientRequirement.sameTeamIdentifier {
                    clientRequirement = try sameTeamRequirement && .sameParentBundle
                } else {
                    clientRequirement = try .sameParentBundle
                }
            }
            
            return MachServiceCriteria(machServiceName: bundleID, clientRequirement: clientRequirement)
        }
    }
}

// MARK: validation result

private enum ValidationResult {
    case success
    case failure(String)
    
    var didSucceed: Bool {
        switch self {
            case .success:
                return true
            case .failure(_):
                return false
        }
    }
    
    func throwIfFailure() throws {
        switch self {
            case .success:
                break
            case .failure(let description):
                throw XPCError.misconfiguredServer(description: description)
        }
    }
}

// MARK: Blessed helper tool

/// Read the property list embedded within this helper tool.
///
/// - Returns: The property list as data.
private func readEmbeddedPropertyList(sectionName: String) throws -> Data {
    // By passing in nil, this returns a handle for the dynamic shared object (shared library) for this helper tool
    guard let handle = dlopen(nil, RTLD_LAZY) else {
        throw XPCError.misconfiguredServer(description: "Could not read property list (handle not openable)")
    }
    defer { dlclose(handle) }
    
    guard let mhExecutePointer = dlsym(handle, MH_EXECUTE_SYM) else {
        throw XPCError.misconfiguredServer(description: "Could not read property list (nil symbol pointer)")
    }
    let mhExecuteBoundPointer = mhExecutePointer.assumingMemoryBound(to: mach_header_64.self)

    var size = UInt()
    guard let section = getsectiondata(mhExecuteBoundPointer, "__TEXT", sectionName, &size) else {
        throw XPCError.misconfiguredServer(description: "Missing property list section \(sectionName)")
    }
    
    return Data(bytes: section, count: Int(size))
}

/// Validates this process is a valid blessed helper tool, intentionally not taking into account whether it has an XPC Mach service.
private func validateThisProcessIsABlessedHelperTool() -> ValidationResult {
    // Following comments describe what must be true for this to be a blessed (privileged) helper tool:

    // Located in: /Library/PrivilegedHelperTools/
    guard Bundle.main.bundleURL == URL(fileURLWithPath: "/Library/PrivilegedHelperTools") else {
        return .failure("""
        A blessed helper tool must be located in directory: /Library/PrivilegedHelperTools
        Actual location: \(Bundle.main.bundleURL)
        """)
    }
    
    // Executable (not a bundle)
    guard let executableURL = Bundle.main.executableURL,
          let firstFourBytes = try? FileHandle(forReadingFrom: executableURL).readData(ofLength: 4),
          firstFourBytes.count == 4 else {
        return .failure("A blessed helper tool must be an executable file")
    }
    let magicValue = firstFourBytes.withUnsafeBytes { pointer in
        pointer.load(fromByteOffset: 0, as: UInt32.self)
    }
    let machOMagicValues: Set<UInt32> = [MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64, FAT_MAGIC, FAT_CIGAM]
    guard machOMagicValues.contains(magicValue) else {
        return .failure("A blessed helper tool must be a Mach-O executable file")
    }
    
    // Embedded __launchd_plist section that has a Label entry which matches this executable name
    guard let launchdData = try? readEmbeddedPropertyList(sectionName: "__launchd_plist"),
          let launchdPlist = try? PropertyListSerialization.propertyList(from: launchdData,
                                                                         format: nil) as? [String : Any],
          let label = launchdPlist["Label"] as? String,
          executableURL.lastPathComponent == label else {
        return .failure("""
        A blessed helper tool have a Label entry in its embedded launchd property list with a value equal to the name
        of its executable file
        """)
    }
    
    // Embedded __info_plist section with a SMAuthorizedClients entry
    guard let infoData = try? readEmbeddedPropertyList(sectionName: "__info_plist"),
          let infoPlist = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String : Any],
          infoPlist.keys.contains("SMAuthorizedClients") else {
        return .failure("A blessed helper tool have a SMAuthorizedClients entry in its embedded info property list")
    }
    
    return .success
}

/// Extract the `MachServices` key values from the embedded launchd property list
private func blessedHelperToolMachServices() throws -> Set<String> {
    let data = try readEmbeddedPropertyList(sectionName: "__launchd_plist")
    guard let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary else {
        throw XPCError.misconfiguredServer(description: "No launchd property list is embedded in executable")
    }
    guard let machServices = propertyList["MachServices"] as? [String : Any] else {
        throw XPCError.misconfiguredServer(description: "launchd property list missing MachServices key")
    }
    if machServices.isEmpty {
        throw XPCError.misconfiguredServer(description: "MachServices has no entries")
    }
    
    return Set<String>(machServices.keys)
}

/// Generate client requirements from the embedded info property list's `SMAuthorizedClients`
private func blessedHelperToolClientRequirements() throws -> XPCClientRequirement {
    // Read authorized clients
    let data = try readEmbeddedPropertyList(sectionName: "__info_plist")
    guard let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary else {
        throw XPCError.misconfiguredServer(description: "No info property list is embedded in executable")
    }
    guard let authorizedClients = propertyList["SMAuthorizedClients"] as? [String] else {
        throw XPCError.misconfiguredServer(description: "Info property list missing SMAuthorizedClients key")
    }
    
    // Turn into client requirement
    var clientRequirement: XPCClientRequirement? = nil
    for client in authorizedClients {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(client as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement = requirement else {
            throw XPCError.misconfiguredServer(description: "Invalid SMAuthorizedClients requirement: \(client)")
        }
        
        if let currentRequirement = clientRequirement {
            clientRequirement = currentRequirement || .secRequirement(requirement)
        } else {
            clientRequirement = .secRequirement(requirement)
        }
    }
    guard let clientRequirement = clientRequirement else {
        throw XPCError.misconfiguredServer(description: "No requirements were generated from SMAuthorizedClients")
    }
    
    return clientRequirement
}

// MARK: Login item

private func validateThisProcessIsALoginItem() -> ValidationResult {
    // Login item must be a bundle
    let loginItem = Bundle.main.bundleURL
    guard loginItem.pathExtension == "app" else {
        return .failure("A login item must be an app bundle.")
    }
    
    // Login item must be within the main bundle's Contents/Library/LoginItems directory
    let pathComponents = loginItem.deletingLastPathComponent().pathComponents
    guard pathComponents.count >= 3, pathComponents.suffix(3) == ["Contents", "Library", "LoginItems"] else {
        return .failure("""
        A login item must be located within its parent bundle's Contents/Library/LoginItems directory.
        Path:\(Bundle.main.bundleURL)
        """)
    }
    
    return .success
}

/// If this process is sandboxed, then the login item *must* have an application group entitlement in order to enable XPC communication. (Non-sandboxed apps
/// cannot have one as this entitlement only applies to the sandbox - it's not part of the hardened runtime.)
private func throwIfSandboxedAndThisLoginItemCannotCommunicateOverXPC() throws {
    guard try isSandboxed() else {
        return
    }
    
    let entitlementName = "com.apple.security.application-groups"
    let entitlement = try readEntitlement(name: entitlementName)
    guard let entitlement = entitlement else {
        throw XPCError.misconfiguredServer(description: """
        Application groups entitlement \(entitlementName) is missing, but must be present for a sandboxed login item \
        to communicate over XPC.
        """)
    }
    guard CFGetTypeID(entitlement) == CFArrayGetTypeID(), let entitlement = (entitlement as? NSArray) else {
        throw XPCError.misconfiguredServer(description: """
        Application groups entitlement \(entitlementName) must be an array of strings.
        """)
    }
    let appGroups = try entitlement.map { (element: NSArray.Element) throws -> String in
        guard let elementAsString = element as? String else {
            throw XPCError.misconfiguredServer(description: """
            Application groups entitlement \(entitlementName) must be an array of strings.
            """)
        }
        
        return elementAsString
    }
    
    guard let teamIdentifier = try teamIdentifierForThisProcess() else {
        throw XPCError.misconfiguredServer(description: """
        A sandboxed login item must have a team identifier in order to communicate over XPC.
        """)
    }
    
    // From https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups
    //     For macOS the format is: <team identifier>.<group name>
    //
    // So for XPC communication to succeed at least one app group must start with this login item's team identifier
    // followed by a period.
    if !appGroups.contains(where: { $0.starts(with: "\(teamIdentifier).") }) {
        throw XPCError.misconfiguredServer(description: """
        Application groups entitlement \(entitlementName) must contain at least one application group for team \
        identifier \(teamIdentifier). Application groups:
        \(appGroups.joined(separator: "\n"))
        """)
    }
}

// MARK: SMAppService daemon & agent

private func parentAppURL() throws -> URL {
    let components = Bundle.main.bundleURL.pathComponents
    guard let contentsIndex = components.lastIndex(of: "Contents"),
          components[components.index(before: contentsIndex)].hasSuffix(".app") else {
        throw XPCError.misconfiguredServer(description: """
        Parent bundle could not be found.
        Path:\(Bundle.main.bundleURL)
        """)
    }
    
    return URL(fileURLWithPath: "/" + components[1..<contentsIndex].joined(separator: "/"))
}

private enum LibraryDirectory: String {
    case daemon = "LaunchDaemons"
    case agent = "LaunchAgents"
}

private func plistsForDaemonOrAgent(parentURL: URL, directory: LibraryDirectory) throws -> [[String : Any]] {
    // For a daemon, from Apple:
    //   The property list name must correspond to a property list in the calling app’s
    //   Contents/Library/LaunchDaemons directory
    //
    // For an agent, from Apple:
    //   The property list name must correspond to a property list in the calling app’s
    //   Contents/Library/LaunchAgents directory.
    guard let executableURL = Bundle.main.executableURL else {
        throw XPCError.misconfiguredServer(description: "This process lacks an executable URL")
    }
    let plistDirectory = parentURL.appendingPathComponent("Contents", isDirectory: true)
                                  .appendingPathComponent("Library", isDirectory: true)
                                  .appendingPathComponent(directory.rawValue, isDirectory: true)
    let plistDirectoryContents = try FileManager.default.contentsOfDirectory(at: plistDirectory,
                                                                             includingPropertiesForKeys: nil)
    let plistsData = plistDirectoryContents.compactMap { try? Data(contentsOf: $0) }
    let plists = plistsData.compactMap {
        try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String : Any]
    }
    let matchingPlists = plists.filter {
        guard let bundleProgram = $0["BundleProgram"] as? String else {
            return false
        }
        return URL(string: bundleProgram, relativeTo: parentURL)?.absoluteURL == executableURL
    }
    
    return matchingPlists
}

private func agentOrDaemonMachServices(directory: LibraryDirectory) throws -> Set<String> {
    let parentURL = try parentAppURL()
    let plists = try plistsForDaemonOrAgent(parentURL: parentURL, directory: directory)
    let serviceNames = Set<String>(plists.flatMap { ($0["MachServices"] as? [String : Any] ?? [:]).keys })
    
    if serviceNames.isEmpty {
        throw XPCError.misconfiguredServer(description: "No MachServices entries")
    }
    
    return serviceNames
}

private func validateThisProcessIsAnSMAppServiceDaemon() -> ValidationResult {
    guard let parentURL = try? parentAppURL(),
          let propertyLists = try? plistsForDaemonOrAgent(parentURL: parentURL, directory: .daemon),
          !propertyLists.isEmpty else {
        return .failure("""
        An SMAppService daemon must have a property list within its parent bundle's Contents/Library/LaunchDaemons /
        directory.
        """)
    }
    
    return .success
}

private func validateThisProcessIsAnSMAppServiceAgent() -> ValidationResult {
    guard let parentURL = try? parentAppURL(),
          let propertyLists = try? plistsForDaemonOrAgent(parentURL: parentURL, directory: .agent),
          !propertyLists.isEmpty else {
        return .failure("""
        An SMAppService agent must have a property list within its parent bundle's Contents/Library/LaunchAgents /
        directory.
        """)
    }
    
    return .success
}
