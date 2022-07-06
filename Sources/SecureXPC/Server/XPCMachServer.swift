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
    private init(machServiceName: String, clientRequirement: XPCClientRequirement) {
        self.machServiceName = machServiceName
        let listenerQueue = DispatchQueue(label: String(describing: XPCMachServer.self))
        // Attempts to bind to the Mach service. If this isn't actually a Mach service a EXC_BAD_INSTRUCTION will occur.
        self.listenerConnection = machServiceName.withCString { namePointer in
            xpc_connection_create_mach_service(namePointer, listenerQueue, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
        }
        self.listenerQueue = listenerQueue
        super.init(clientRequirement: clientRequirement)
        
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
    
    public override var endpoint: XPCServerEndpoint {
        XPCServerEndpoint(connectionDescriptor: .machService(name: self.machServiceName),
                          endpoint: xpc_endpoint_create(self.listenerConnection))
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
                                          clientRequirement: XPCClientRequirement) throws -> XPCMachServer {
        // Force serial execution to prevent a race condition where multiple XPCMachServer instances for the same Mach
        // service name are created and returned
        try serialQueue.sync {
            let server: XPCMachServer
            if let cachedServer = machServerCache[machServiceName] {
                guard clientRequirement == cachedServer.clientRequirement else {
                    throw XPCError.conflictingClientRequirements
                }
                server = cachedServer
            } else {
                server = XPCMachServer(machServiceName: machServiceName, clientRequirement: clientRequirement)
                machServerCache[machServiceName] = server
            }
            
            return server
        }
    }
    
    // MARK: Blessed Helper Tool
    
    internal static var isThisProcessABlessedHelperTool: Bool {
        // Following comments describe what must be true for this to be a blessed (privileged) helper tool:

        // Located in: /Library/PrivilegedHelperTools/
        guard Bundle.main.bundleURL == URL(fileURLWithPath: "/Library/PrivilegedHelperTools") else {
            return false
        }
        
        // Executable (not a bundle)
        guard let executableURL = Bundle.main.executableURL,
              let firstFourBytes = try? FileHandle(forReadingFrom: executableURL).readData(ofLength: 4),
              firstFourBytes.count == 4 else {
            return false
        }
        let magicValue = firstFourBytes.withUnsafeBytes { pointer in
            pointer.load(fromByteOffset: 0, as: UInt32.self)
        }
        let machOMagicValues: Set<UInt32> = [MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64, FAT_MAGIC, FAT_CIGAM]
        guard machOMagicValues.contains(magicValue) else {
            return false
        }
        
        // Embedded __launchd_plist section that has a Label entry which matches this executable name
        guard let launchdData = try? readEmbeddedPropertyList(sectionName: "__launchd_plist"),
              let launchdPlist = try? PropertyListSerialization.propertyList(from: launchdData, format: nil) as? [String : Any],
              let label = launchdPlist["Label"] as? String,
              executableURL.lastPathComponent == label else {
            return false
        }
        
        // Embedded __info_plist section with a SMAuthorizedClients entry
        guard let infoData = try? readEmbeddedPropertyList(sectionName: "__info_plist"),
              let infoPlist = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String : Any],
              infoPlist.keys.contains("SMAuthorizedClients") else {
            return false
        }
        
        return true
    }
    
    internal static func forThisBlessedHelperTool() throws -> XPCMachServer {
        // Determine mach service name using the launchd property list's MachServices entry
        let machServiceName: String
        let launchdData = try readEmbeddedPropertyList(sectionName: "__launchd_plist")
        let launchdPropertyList = try PropertyListSerialization.propertyList(
            from: launchdData,
            options: .mutableContainersAndLeaves,
            format: nil) as? NSDictionary
        if let machServices = launchdPropertyList?["MachServices"] as? [String : Any] {
            if machServices.count == 1, let name = machServices.first?.key {
                machServiceName = name
            } else {
                throw XPCError.misconfiguredServer(description: "MachServices dictionary must have exactly one entry")
            }
        } else {
            throw XPCError.misconfiguredServer(description: "launchd property list missing MachServices key")
        }

        // Generate client requirements from info property list's SMAuthorizedClients
        let infoData = try readEmbeddedPropertyList(sectionName: "__info_plist")
        let infoPropertyList = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? NSDictionary
        guard let authorizedClients = infoPropertyList?["SMAuthorizedClients"] as? [String] else {
            throw XPCError.misconfiguredServer(description: "Info property list missing SMAuthorizedClients key")
        }
        
        var clientRequirement: XPCClientRequirement? = nil
        for client in authorizedClients {
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(client as CFString, SecCSFlags(), &requirement) == errSecSuccess,
                  let requirement = requirement else {
                throw XPCError.misconfiguredServer(description: "Invalid SMAuthorizedClients requirement: \(client)")
            }
            
            if let currentRequirement = clientRequirement {
                clientRequirement = .or(currentRequirement, .secRequirement(requirement))
            } else {
                clientRequirement = .secRequirement(requirement)
            }
        }
        guard let clientRequirement = clientRequirement else {
            throw XPCError.misconfiguredServer(description: "No requirements were generated from SMAuthorizedClients")
        }

        return try getXPCMachServer(named: machServiceName, clientRequirement: clientRequirement)
    }

    /// Read the property list embedded within this helper tool.
    ///
    /// - Returns: The property list as data.
    private static func readEmbeddedPropertyList(sectionName: String) throws -> Data {
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
    
    // MARK: daemon & agent
    
    private static func parentAppURL() throws -> URL {
        let components = Bundle.main.bundleURL.pathComponents
        guard let contentsIndex = components.lastIndex(of: "Contents"),
              components[components.index(before: contentsIndex)].hasSuffix(".app") else {
            throw XPCError.misconfiguredServer(description: "Parent bundle could not be found")
        }
        
        return URL(fileURLWithPath: "/" + components[1..<contentsIndex].joined(separator: "/"))
    }
    
    // directoryName is expected to be one of:
    // - LaunchDaemons
    // - LaunchAgents
    private static func plistsForDaemonOrAgent(parentURL: URL, directoryName: String) throws -> [[String : Any]] {
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
                                      .appendingPathComponent(directoryName, isDirectory: true)
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
    
    private static func machServices(propertyLists: [[String : Any]]) throws -> Set<String> {
        Set<String>(propertyLists.flatMap { ($0["MachServices"] as? [String : Any] ?? [:]).keys })
    }
    
    private static func machServiceNameForAgentOrDaemon() throws -> String {
        let parentURL = try parentAppURL()
        let plists = try plistsForDaemonOrAgent(parentURL: parentURL, directoryName: "LaunchDaemons")
        let serviceNames = try machServices(propertyLists: plists)

        // We can't actually know which property list was used to register this service, so if there are multiple
        // conflicting ones we need to fail (and of course also fail if there are none). The same applies if there was
        // only one property list, but it had multiple MachServices entries.
        guard serviceNames.count == 1, let serviceName = serviceNames.first else {
            if serviceNames.isEmpty {
                throw XPCError.misconfiguredServer(description: "No property lists for had a MachServices entry")
            } else {
                throw XPCError.misconfiguredServer(description: "Multiple MachServices keys found: \(serviceNames)")
            }
        }
        
        return serviceName
    }
    
    // MARK: daemon
    
    internal static var isThisProcessADaemon: Bool {
        guard let parentURL = try? parentAppURL(),
              let machServices = try? plistsForDaemonOrAgent(parentURL: parentURL, directoryName: "LaunchDaemons") else {
            return false
        }
        
        return !machServices.isEmpty
    }
    
    internal static func forThisDaemon() throws -> XPCMachServer {
        let serviceName = try machServiceNameForAgentOrDaemon()

        // Use the parent's designated requirement as the criteria for the message acceptor. An alternative approach
        // would be to use the same approach as Login Item where we allow anything in the parent's bundle with the same
        // team identifier to communicate with this daemon, but considering the considerable privilege escalation
        // potential this intentionally takes a more restricted approach.
        let clientRequirement = try XPCClientRequirement.parentDesignatedRequirement
        
        return try getXPCMachServer(named: serviceName, clientRequirement: clientRequirement)
    }
    
    // MARK: agent
    
    internal static var isThisProcessAnAgent: Bool {
        guard let parentURL = try? parentAppURL(),
              let machServices = try? plistsForDaemonOrAgent(parentURL: parentURL, directoryName: "LaunchAgents") else {
            return false
        }
        
        return !machServices.isEmpty
    }
    
    internal static func forThisAgent() throws -> XPCMachServer {
        let serviceName = try machServiceNameForAgentOrDaemon()

        // Use the team identifier as the criteria for the message acceptor. An alternative approach would be to use
        // the parent's designated requirement or restrict to within the parent's app bundle, but if either of those
        // were the desired use case for this launch agent then in most cases an XPC service would be a better fit. If a
        // launch agent is being used it's reasonable to default to allowing requests from outside of the app bundle as
        // long as it's from the same team identifier.
        let clientRequirement = try XPCClientRequirement.sameTeamIdentifier
        
        return try getXPCMachServer(named: serviceName, clientRequirement: clientRequirement)
    }
    
    // MARK: Login Item
    
    internal static var isThisProcessALoginItem: Bool {
        // Login item must be a bundle
        let loginItem = Bundle.main.bundleURL
        guard loginItem.pathExtension == "app" else {
            return false
        }
        
        // Login item must be within the main bundle's Contents/Library/LoginItems directory
        let pathComponents = loginItem.deletingLastPathComponent().pathComponents
        guard pathComponents.count >= 3, pathComponents.suffix(3) == ["Contents", "Library", "LoginItems"] else {
            return false
        }
        
        return true
    }
    
    internal static func forThisLoginItem() throws -> XPCMachServer {
        guard let teamIdentifier = try teamIdentifierForThisProcess() else {
            throw XPCError.misconfiguredServer(description: "A login item must have a team identifier in order to " +
                                                            "enable secure communication.")
        }
        try validateIsLoginItem(teamIdentifier: teamIdentifier)
        
        // From Apple's AppSandboxLoginItemXPCDemo:
        // https://developer.apple.com/library/archive/samplecode/AppSandboxLoginItemXPCDemo/
        //     LaunchServices implicitly registers a Mach service for the login item whose name is the same as the
        //     login item's bundle identifier.
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw XPCError.misconfiguredServer(description: "The bundle identifier is missing; login items must have " +
                                                            "one.")
        }
        let clientRequirement = try XPCClientRequirement.and(.teamIdentifier(teamIdentifier), .sameParentBundle)
        
        return try getXPCMachServer(named: bundleID, clientRequirement: clientRequirement)
    }
    
    private static func validateIsLoginItem(teamIdentifier: String) throws {
        guard isThisProcessALoginItem else {
            throw XPCError.misconfiguredServer(description: """
            A login item must be an app bundle located within its parent bundle's Contents/Library/LoginItems directory.
            Path:\(Bundle.main.bundleURL)
            """)
        }
        
        if try isSandboxed() {
            // If this process is sandboxed, then the login item *must* have an application group entitlement in order
            // to enable XPC communication. (Non-sandboxed apps cannot have one as this entitlement only applies to the
            // sandbox - it's not part of the hardened runtime.)
            let entitlementName = "com.apple.security.application-groups"
            
            let entitlement = try readEntitlement(name: entitlementName)
            guard let entitlement = entitlement else {
                throw XPCError.misconfiguredServer(description: "Application groups entitlement \(entitlementName) " +
                                                                "is missing, but must be  present for a sandboxed " +
                                                                "login item to communicate over XPC.")
            }
            guard CFGetTypeID(entitlement) == CFArrayGetTypeID(), let entitlement = (entitlement as? NSArray) else {
                throw XPCError.misconfiguredServer(description: "Application groups entitlement \(entitlementName) " +
                                                                "must be an array of strings.")
            }
            let appGroups = try entitlement.map { (element: NSArray.Element) throws -> String in
                guard let elementAsString = element as? String else {
                    throw XPCError.misconfiguredServer(description: "Application groups entitlement " +
                                                                    "\(entitlementName) must be an array of strings.")
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
                throw XPCError.misconfiguredServer(description: message)
            }
        }
    }
}
