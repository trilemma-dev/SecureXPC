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
            serviceDescriptor: .machService(name: self.machServiceName),
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
    
    internal static func _forThisLoginItem() throws -> XPCMachServer {
        // There's no public way to definitively determine this code is actually running as part of a login item, but
        // at a minimum it's possible to determine if we're *not* one based on the required directory structure.
        //
        // From SMLoginItemSetEnabled:
        // https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled
        //     Enables a helper tool in the main app bundle’s Contents/Library/LoginItems directory.
        func validatePathComponent(_ path: URL, expectedLastComponent: String) throws -> URL {
            if path.lastPathComponent != expectedLastComponent {
                let message = "A login item helper tool must be located within the main app bundle's " +
                              "Contents/Library/LoginItems directory.\n" +
                              "Expected path component: \(expectedLastComponent)\n" +
                              "Actual path component: \(path.lastPathComponent)"
                throw XPCError.misconfiguredLoginItem(message)
            }
            
            return path.deletingLastPathComponent()
        }
        
        let loginItemsDir = Bundle.main.bundleURL.deletingLastPathComponent() // removes the login item's app bundle
        let libraryDir = try validatePathComponent(loginItemsDir, expectedLastComponent: "LoginItems")
        let contentsDir = try validatePathComponent(libraryDir, expectedLastComponent: "Library")
        let parentAppBundle = try validatePathComponent(contentsDir, expectedLastComponent: "Contents")
        
        if parentAppBundle.pathExtension != "app" {
            let message = "A login item helper tool must be located within a main app bundle, but the containing " +
                          "directory is not an app bundle.\n" +
                          "Expected path extension: app\n" +
                          "Actual path extension: \(parentAppBundle.pathExtension)"
            throw XPCError.misconfiguredLoginItem(message)
        }
        
        // Note: due to sandboxing, there's a good chance we can't actually access the parent app bundle to do any sort
        // of validation (like checking it's actually a bundle) or reading its Info.plist
        
        // From Apple's AppSandboxLoginItemXPCDemo:
        // https://developer.apple.com/library/archive/samplecode/AppSandboxLoginItemXPCDemo/
        //     LaunchServices implicitly registers a mach service for the login item whose name is the same as the
        //     login item's bundle identifier.
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw XPCError.misconfiguredLoginItem("The bundle identifier is missing; login items must have one")
        }
        
        return try getXPCMachServer(named: bundleID, messageAcceptor: ParentBundleMessageAcceptor.instance)
    }

    internal static func _forThisBlessedHelperTool() throws -> XPCMachServer {
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
                throw XPCError.misconfiguredBlessedHelperTool("MachServices dictionary does not have exactly one entry")
            }
        } else {
            throw XPCError.misconfiguredBlessedHelperTool("launchd property list missing MachServices key")
        }

        // Generate client requirements from info property list's SMAuthorizedClients
        var clientRequirements = [SecRequirement]()
        let infoData = try readEmbeddedPropertyList(sectionName: "__info_plist")
        let infoPropertyList = try PropertyListSerialization.propertyList(
            from: infoData,
            options: .mutableContainersAndLeaves,
            format: nil) as? NSDictionary
        if let authorizedClients = infoPropertyList?["SMAuthorizedClients"] as? [String] {
            for client in authorizedClients {
                var requirement: SecRequirement?
                if SecRequirementCreateWithString(client as CFString, SecCSFlags(), &requirement) == errSecSuccess,
                   let requirement = requirement {
                    clientRequirements.append(requirement)
                } else {
                    throw XPCError.misconfiguredBlessedHelperTool("Invalid SMAuthorizedClients requirement: \(client)")
                }
            }
        } else {
            throw XPCError.misconfiguredBlessedHelperTool("Info property list missing SMAuthorizedClients key")
        }
        if clientRequirements.isEmpty {
            throw XPCError.misconfiguredBlessedHelperTool("No requirements were generated from SMAuthorizedClients")
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
            throw XPCError.misconfiguredBlessedHelperTool("Could not read property list (handle not openable)")
        }
        defer { dlclose(handle) }
        
        guard let mhExecutePointer = dlsym(handle, MH_EXECUTE_SYM) else {
            throw XPCError.misconfiguredBlessedHelperTool("Could not read property list (nil symbol pointer)")
        }
        let mhExecuteBoundPointer = mhExecutePointer.assumingMemoryBound(to: mach_header_64.self)

        var size = UInt()
        guard let section = getsectiondata(mhExecuteBoundPointer, "__TEXT", sectionName, &size) else {
            throw XPCError.misconfiguredBlessedHelperTool("Missing property list section \(sectionName)")
        }
        
        return Data(bytes: section, count: Int(size))
    }
}
