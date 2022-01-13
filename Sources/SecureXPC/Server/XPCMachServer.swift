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
    private var listenerConnection: xpc_connection_t
    /// Determines if an incoming request will be accepted based on the provided client requirements
    private let _messageAcceptor: SecureMessageAcceptor
    override internal var messageAcceptor: MessageAcceptor {
        _messageAcceptor
    }
    
    /// This should only ever be called from `getXPCMachServer(...)` so that client requirement invariants are upheld.
    private init(machServiceName: String, clientRequirements: [SecRequirement]) {
        self.machServiceName = machServiceName
        self._messageAcceptor = SecureMessageAcceptor(requirements: clientRequirements)
        
        // Attempts to bind to the Mach service. If this isn't actually a Mach service a EXC_BAD_INSTRUCTION will occur.
        self.listenerConnection = machServiceName.withCString { serviceNamePointer in
            return xpc_connection_create_mach_service(
                serviceNamePointer,
                nil,
                UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
        }
        super.init()
        self.addConnection(self.listenerConnection)
    }
    
    /// Cache of servers with the machServiceName as the key.
    ///
    /// This exists for correctness reasons, not as a performance optimization. Only one listener connection for a named service can exist simultaneously, so it's
    /// important this invariant be upheld when returning `XPCServer` instances.
    private static var machServerCache = [String : XPCMachServer]()
    
    /// Prevents race conditions for creating and retrieving cached Mach servers
    private static let serialQueue = DispatchQueue(label: "XPC Mach Server Serial Queue")
    
    /// Returns a server with the provided name and requirements OR throws an error if that's not possible.
    ///
    /// Decision tree:
    /// - If a server exists with that name:
    ///   - If the client requirements match, return the server.
    ///   - Else the client requirements do not match, throw an error.
    /// - Else no server exists in the cache with the provided name, create one, store it in the cache, and return it.
    ///
    /// This behavior prevents ending up with two servers for the same named XPC Mach service.
    internal static func getXPCMachServer(named machServiceName: String,
                                          clientRequirements: [SecRequirement]) throws -> XPCMachServer {
        // Force serial execution to prevent a race condition where multiple XPCMachServer instances for the same Mach
        // service name are created and returned
        try serialQueue.sync {
            let server: XPCMachServer
            if let cachedServer = machServerCache[machServiceName] {
                // Transform the requirements into Data form so that they can be compared
                let requirementTransform = { (requirement: SecRequirement) throws -> Data in
                    var data: CFData?
                    if SecRequirementCopyData(requirement, [], &data) == errSecSuccess,
                       let data = data as Data? {
                        return data
                    } else {
                        throw XPCError.unknown
                    }
                }
                
                // Turn into sets so they can be compared without taking into account the order of requirements
                let requirementsData = Set<Data>(try clientRequirements.map(requirementTransform))
                let cachedRequirementsData = Set<Data>(try cachedServer._messageAcceptor.requirements
                                                                       .map(requirementTransform))
                guard requirementsData == cachedRequirementsData else {
                    throw XPCError.conflictingClientRequirements
                }
                
                server = cachedServer
            } else {
                server = XPCMachServer(machServiceName: machServiceName, clientRequirements: clientRequirements)
                machServerCache[machServiceName] = server
            }
            
            return server
        }
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

		return try getXPCMachServer(named: machServiceName, clientRequirements: clientRequirements)
	}

	/// Read the property list embedded within this helper tool.
	///
	/// - Returns: The property list as data.
	private static func readEmbeddedPropertyList(sectionName: String) throws -> Data {
		// By passing in nil, this returns a handle for the dynamic shared object (shared library) for this helper tool
		if let handle = dlopen(nil, RTLD_LAZY) {
			defer { dlclose(handle) }

			if let mhExecutePointer = dlsym(handle, MH_EXECUTE_SYM) {
				let mhExecuteBoundPointer = mhExecutePointer.assumingMemoryBound(to: mach_header_64.self)

				var size = UInt(0)
				if let section = getsectiondata(mhExecuteBoundPointer, "__TEXT", sectionName, &size) {
					return Data(bytes: section, count: Int(size))
				} else { // No section found with the name corresponding to the property list
					throw XPCError.misconfiguredBlessedHelperTool("Missing property list section \(sectionName)")
				}
			} else { // Can't get pointer to MH_EXECUTE_SYM
				throw XPCError.misconfiguredBlessedHelperTool("Could not read property list (nil symbol pointer)")
			}
		} else { // Can't open handle
			throw XPCError.misconfiguredBlessedHelperTool("Could not read property list (handle not openable)")
		}
	}
    
	public override func startAndBlock() -> Never {
        self.start()

        // Park the main thread, allowing for incoming connections and requests to be processed
        dispatchMain()
	}
}

extension XPCMachServer: NonBlockingServer {
    public func start() {
        // Set listener for the Mach service, all received events will be incoming connections
        xpc_connection_set_event_handler(listenerConnection, { connection in
            // Listen for events (messages or errors) coming from this connection
            xpc_connection_set_event_handler(connection, { event in
                self.handleEvent(connection: connection, event: event)
            })
            xpc_connection_set_target_queue(connection, self.targetQueue)
            self.addConnection(connection)
            xpc_connection_resume(connection)
        })
        xpc_connection_resume(listenerConnection)
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
