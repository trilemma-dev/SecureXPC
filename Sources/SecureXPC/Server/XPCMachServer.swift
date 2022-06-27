//
//  XPCMachServer.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-08
//

import Foundation

/// A concrete implementation of ``XPCServer`` which acts as a server for an XPC Mach service.
///
/// In the case of this framework, the XPC Service is expected to be communicated with by an `XPCMachClient`.
internal class XPCMachServer: XPCServer {
    /// Name of the service.
    private let machServiceName: String
    /// Receives new incoming connections
    private let listenerConnection: xpc_connection_t
    /// The dispatch queue used when new connections are being received
    private let listenerQueue: DispatchQueue
    /// Whether this server has been started, if not connections are added to pendingConnections
    private var started = false
    /// Connections received while the server is not started
    private var pendingConnections = [xpc_connection_t]()
    
    /// This should only ever be called from `getXPCMachServer(...)` so that client requirement invariants are upheld.
    private init(machServiceName: String, messageAcceptor: MessageAcceptor) {
        self.machServiceName = machServiceName
        let listenerQueue = DispatchQueue(label: String(describing: XPCMachServer.self))
        // Attempts to bind to the Mach service. If this isn't actually a Mach service a EXC_BAD_INSTRUCTION will occur.
        self.listenerConnection = machServiceName.withCString { namePointer in
            xpc_connection_create_mach_service(namePointer, listenerQueue, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
        }
        self.listenerQueue = listenerQueue
        super.init(messageAcceptor: messageAcceptor)
        
        // Configure listener for new connections, all received events are incoming client connections
        xpc_connection_set_event_handler(self.listenerConnection, { connection in
            if self.started {
                self.startClientConnection(connection)
            } else {
                self.pendingConnections.append(connection)
            }
        })
        xpc_connection_resume(self.listenerConnection)
    }
    
    public override func startAndBlock() -> Never {
        self.start()

        // Park the main thread, allowing for incoming connections and requests to be processed
        dispatchMain()
    }
    
    public override var connectionDescriptor: XPCConnectionDescriptor {
        .machService(name: machServiceName)
    }
}

extension XPCMachServer: XPCNonBlockingServer {
    public func start() {
        self.listenerQueue.sync {
            self.started = true
            for connection in self.pendingConnections {
                self.startClientConnection(connection)
            }
            self.pendingConnections.removeAll()
        }
    }
    
    public var endpoint: XPCServerEndpoint {
        XPCServerEndpoint(
            connectionDescriptor: .machService(name: self.machServiceName),
            endpoint: xpc_endpoint_create(self.listenerConnection)
        )
    }
}

extension XPCMachServer: CustomDebugStringConvertible {
    /// Description which includes the name of the service and its memory address (to help in debugging uniqueness bugs)
    var debugDescription: String {
        "\(XPCMachServer.self) [\(self.machServiceName)] \(Unmanaged.passUnretained(self).toOpaque())"
    }
}

/// Contains all of the `static` code that provides the entry points to retrieving an `XPCMachServer` instance.
extension XPCMachServer {
    /// Cache of servers with the machServiceName as the key.
    ///
    /// This exists for correctness reasons, not as a performance optimization. Only one listener connection for a named service can exist simultaneously, so it's
    /// important this invariant be upheld when returning `XPCServer` instances.
    private static var machServerCache = [String : XPCMachServer]()
    
    /// Prevents race conditions for creating and retrieving cached Mach servers
    private static let serialQueue = DispatchQueue(label: "XPCMachServer Retrieval Queue")
    
    /// Returns a server with the provided name and an equivalent message acceptor OR throws an error if that's not possible.
    ///
    /// Decision tree:
    /// - If a server exists with that name:
    ///   - If the message acceptors are equivalent, return the server.
    ///   - Else, throw an error.
    /// - Else no server exists in the cache with the provided name, create one, store it in the cache, and return it.
    ///
    /// This behavior prevents ending up with two servers for the same named XPC Mach service.
    internal static func getXPCMachServer(named machServiceName: String,
                                          messageAcceptor: MessageAcceptor) throws -> XPCMachServer {
        // Force serial execution to prevent a race condition where multiple XPCMachServer instances for the same Mach
        // service name are created and returned
        try serialQueue.sync {
            let server: XPCMachServer
            if let cachedServer = machServerCache[machServiceName] {
                if !messageAcceptor.isEqual(to: cachedServer.messageAcceptor) {
                    throw XPCError.conflictingClientRequirements
                }
                server = cachedServer
            } else {
                server = XPCMachServer(machServiceName: machServiceName, messageAcceptor: messageAcceptor)
                machServerCache[machServiceName] = server
            }
            
            return server
        }
    }
    
    // MARK: Blessed Helper Tool
    
    internal static func _forThisBlessedHelperTool() throws -> XPCMachServer {
        // Determine mach service name using the launchd property list's MachServices entry
        let machServiceName: String
        let launchdData = try readEmbeddedPropertyList(sectionName: "__launchd_plist")
        let launchdPlist = try PropertyListSerialization.propertyList(from: launchdData, format: nil) as? [String : Any]
        guard let machServices = launchdPlist?["MachServices"] as? [String : Any] else {
            throw XPCError.misconfiguredBlessedHelperTool(description: "launchd property list missing MachServices key")
        }
        guard machServices.count == 1, let name = machServices.first?.key else {
            throw XPCError.misconfiguredBlessedHelperTool(description: "MachServices dictionary does not have " +
                                                                       "exactly one entry")
        }
        machServiceName = name
        
        // Generate client requirements from info property list's SMAuthorizedClients
        var clientRequirements = [SecRequirement]()
        let infoData = try readEmbeddedPropertyList(sectionName: "__info_plist")
        let infoPlist = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String : Any]
        guard let authorizedClients = infoPlist?["SMAuthorizedClients"] as? [String] else {
            throw XPCError.misconfiguredBlessedHelperTool(description: "Info property list missing " +
                                                                       "SMAuthorizedClients key")
        }
        for client in authorizedClients {
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(client as CFString, SecCSFlags(), &requirement) == errSecSuccess,
               let requirement = requirement else {
                throw XPCError.misconfiguredBlessedHelperTool(description: "Invalid SMAuthorizedClients requirement: " +
                                                                            client)
            }
            clientRequirements.append(requirement)
        }
        if clientRequirements.isEmpty {
            throw XPCError.misconfiguredBlessedHelperTool(description: "No requirements were generated from " +
                                                                       "SMAuthorizedClients")
        }
        let messageAcceptor = SecRequirementsMessageAcceptor(clientRequirements)

        return try getXPCMachServer(named: machServiceName, messageAcceptor: messageAcceptor)
    }

    /// Read the property list embedded within this helper tool.
    ///
    /// - Returns: The property list as data.
    private static func readEmbeddedPropertyList(sectionName: String) throws -> Data {
        // By passing in nil, this returns a handle for the dynamic shared object (shared library) for this helper tool
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            throw XPCError.misconfiguredBlessedHelperTool(description: "Could not read property list (handle not " +
                                                                       "openable)")
        }
        defer { dlclose(handle) }
        
        guard let mhExecutePointer = dlsym(handle, MH_EXECUTE_SYM) else {
            throw XPCError.misconfiguredBlessedHelperTool(description: "Could not read property list (nil symbol " +
                                                                       "pointer)")
        }
        let mhExecuteBoundPointer = mhExecutePointer.assumingMemoryBound(to: mach_header_64.self)

        var size = UInt()
        guard let section = getsectiondata(mhExecuteBoundPointer, "__TEXT", sectionName, &size) else {
            throw XPCError.misconfiguredBlessedHelperTool(description: "Missing property list section \(sectionName)")
        }
        
        return Data(bytes: section, count: Int(size))
    }
    
    // MARK: SMAppService daemon
    
    internal static func _forThisSMAppServiceDaemon() throws -> XPCMachServer {
        // Parent bundle
        let components = Bundle.main.bundleURL.pathComponents
        guard let contentsIndex = components.lastIndex(of: "Contents"),
              components[components.index(before: contentsIndex)].hasSuffix(".app") else {
            throw XPCError.misconfiguredDaemon(description: "Parent bundle could not be found")
        }
        let parentBundleURL = URL(fileURLWithPath: "/" + components[1..<contentsIndex].joined(separator: "/"))
        
        // Determine the service name by finding the launch property list for this service and read their MachServices
        // names. From Apple:
        //   The property list name must correspond to a property list in the calling app’s
        //   Contents/Library/LaunchDaemons directory
        var machServiceNames = Set<String>()
        let plistDirectory = parentBundleURL.appendingPathComponent("Contents", isDirectory: true)
                                            .appendingPathComponent("Library", isDirectory: true)
                                            .appendingPathComponent("LaunchDaemons", isDirectory: true)
        for entry in try FileManager.default.contentsOfDirectory(at: plistDirectory, includingPropertiesForKeys: nil) {
            let data = try Data(contentsOf: entry)
            if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String : Any],
               let bundleProgram = plist["BundleProgram"] as? String,
               let executableURL = Bundle.main.executableURL,
               let bundledProgramURL = URL(string: bundleProgram, relativeTo: parentBundleURL)?.absoluteURL,
               executableURL == bundledProgramURL,
               let services = plist["MachServices"] as? [String : Any] {
                services.keys.forEach { machServiceNames.insert($0) }
            }
        }
        
        // We can't actually know which one was used to register this service, so if there are multiple conflicting ones
        // we need to fail (and of course also fail if there are none)
        guard machServiceNames.count == 1, let serviceName = machServiceNames.first else {
            if machServiceNames.isEmpty {
                throw XPCError.misconfiguredDaemon(description: "No property lists for this daemon had a " +
                                                                "MachServices entry")
            } else {
                throw XPCError.misconfiguredDaemon(description: "Multiple MachServices keys were found: " +
                                                                "\(machServiceNames)")
            }
        }
        
        // Use parent's designated requirement as the criteria for the message acceptor.
        // An alternative approach would be to use the same approach as Login Item where we allow anything in the
        // parent's bundle with the same team identifier to communicate with this daemon, but considering the
        // considerable privilege escalation potential this intentionally takes a more restricted approach.
        var parentCode: SecStaticCode?
        var parentRequirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(parentBundleURL as CFURL, [], &parentCode) == errSecSuccess,
              let parentCode,
              SecCodeCopyDesignatedRequirement(parentCode, [], &parentRequirement) == errSecSuccess,
              let parentRequirement else {
            throw XPCError.misconfiguredDaemon(description: "Designated requirement for parent bundle could not be " +
                                                            "determined")
        }
        let messageAcceptor = SecRequirementsMessageAcceptor([parentRequirement])
        
        return try getXPCMachServer(named: serviceName, messageAcceptor: messageAcceptor)
    }
    
    // MARK: Login Item
    
    internal static func _forThisLoginItem() throws -> XPCMachServer {
        guard let teamIdentifier = try teamIdentifier() else {
            throw XPCError.misconfiguredLoginItem(description: "A login item must have a team identifier in order " +
                                                               "to enable secure communication.")
        }
        
        // From Apple's AppSandboxLoginItemXPCDemo:
        // https://developer.apple.com/library/archive/samplecode/AppSandboxLoginItemXPCDemo/
        //     LaunchServices implicitly registers a Mach service for the login item whose name is the same as the
        //     login item's bundle identifier.
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw XPCError.misconfiguredLoginItem(description: "The bundle identifier is missing; login items must " +
                                                               "have one.")
        }
        
        let parentMessageAcceptor = try validateIsLoginItem(teamIdentifier: teamIdentifier)
        let teamRequirementMessageAcceptor = try messageAcceptor(forTeamIdentifier: teamIdentifier)
        let messageAcceptor = AndMessageAcceptor(lhs: teamRequirementMessageAcceptor, rhs: parentMessageAcceptor)
        
        return try getXPCMachServer(named: bundleID, messageAcceptor: messageAcceptor)
    }
    
    /// The team identifier for this process or `nil` if there isn't one.
    private static func teamIdentifier() throws -> String? {
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        let status = SecCodeCopySigningInformation(try SecStaticCodeCopySelf(), flags, &info)
        guard status == errSecSuccess, let info = info as NSDictionary? else {
            throw XPCError.internalFailure(description: "SecCodeCopySigningInformation failed with status: \(status)")
        }

        return info[kSecCodeInfoTeamIdentifier] as? String
    }
    
    /// Partially validates this process is a login item, and if successful returns a message acceptor which accepts messages from any client located within the
    /// parent bundle of this login item.
    private static func validateIsLoginItem(teamIdentifier: String) throws -> ParentBundleMessageAcceptor {
        // From SMLoginItemSetEnabled:
        // https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled
        //     Enables a helper tool in the main app bundle’s Contents/Library/LoginItems directory.
        func validatePathComponent(_ path: URL, expectedLastComponent: String) throws -> URL {
            if path.lastPathComponent != expectedLastComponent {
                let message = "A login item must be located within the main app bundle's Contents/Library/LoginItems " +
                              "directory.\n" +
                              "Expected path component: \(expectedLastComponent)\n" +
                              "Actual path component: \(path.lastPathComponent)"
                throw XPCError.misconfiguredLoginItem(description: message)
            }
            
            return path.deletingLastPathComponent()
        }
        
        let loginItemsDir = Bundle.main.bundleURL.deletingLastPathComponent() // removes the login item's app bundle
        let libraryDir = try validatePathComponent(loginItemsDir, expectedLastComponent: "LoginItems")
        let contentsDir = try validatePathComponent(libraryDir, expectedLastComponent: "Library")
        let parentBundle = try validatePathComponent(contentsDir, expectedLastComponent: "Contents")
        if parentBundle.pathExtension != "app" {
            let message = "A login item must be located within a main app bundle, but the containing " +
                          "directory is not an app bundle.\n" +
                          "Expected path extension: app\n" +
                          "Actual path extension: \(parentBundle.pathExtension)"
            throw XPCError.misconfiguredLoginItem(description: message)
        }
        
        if try isSandboxed() {
            // If this process is sandboxed, then the login item *must* have an application group entitlement in order
            // to enable XPC communication. (Non-sandboxed apps cannot have one as this entitlement only applies to the
            // sandbox - it's not part of the hardened runtime.)
            let entitlementName = "com.apple.security.application-groups"
            
            let entitlement = try readEntitlement(name: entitlementName)
            guard let entitlement = entitlement else {
                throw XPCError.misconfiguredLoginItem(description: "Application groups entitlement " +
                                                                   "\(entitlementName) is missing, but must be " +
                                                                   "present for a sandboxed login item to " +
                                                                   "communicate over XPC.")
            }
            guard CFGetTypeID(entitlement) == CFArrayGetTypeID(), let entitlement = (entitlement as? NSArray) else {
                throw XPCError.misconfiguredLoginItem(description: "Application groups entitlement " +
                                                                   "\(entitlementName) must be an array of strings.")
            }
            let appGroups = try entitlement.map { (element: NSArray.Element) throws -> String in
                guard let elementAsString = element as? String else {
                    throw XPCError.misconfiguredLoginItem(description: "Application groups entitlement " +
                                                                       "\(entitlementName) must be an array of " +
                                                                       "strings.")
                }
                
                return elementAsString
            }
            
            // From https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups
            //     For macOS the format is: <team identifier>.<group name>
            //
            // So for XPC communication to succeed at least one app group must start with this login item's team
            // identifier followed by a period.
            if !appGroups.contains(where: { $0.starts(with: "\(teamIdentifier).") }) {
                let message = "Application groups entitlement \(entitlementName) must contain at least one " +
                              "application group for team identifier \(teamIdentifier)."
                throw XPCError.misconfiguredLoginItem(description: message)
            }
        }
        
        return ParentBundleMessageAcceptor(parentBundleURL: parentBundle)
    }
    
    private static func messageAcceptor(forTeamIdentifier teamIdentifier: String) throws -> SecRequirementsMessageAcceptor {
        // From https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html
        // In regards to subject.OU:
        //     In Apple issued developer certificates, this field contains the developer’s Team Identifier.
        let teamRequirement = "certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        // Effectively this means the certificate chain was signed by Apple
        let appleRequirement = "anchor apple generic"
        let requirementString = [appleRequirement, teamRequirement].joined(separator: " and ") as CFString
        
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement = requirement else {
            let message = "Security requirement could not be created; textual representation: \(requirementString)"
            throw XPCError.internalFailure(description: message)
        }
        
        return SecRequirementsMessageAcceptor([requirement])
    }
}
