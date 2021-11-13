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
    
    private let machServiceName: String
    private let clientRequirements: [SecRequirement]
    
    /// This should only ever be called from `getXPCMachServer(...)` so that client requirement invariants are upheld.
    private init(machServiceName: String, clientRequirements: [SecRequirement]) {
        self.machServiceName = machServiceName
        self.clientRequirements = clientRequirements
    }
    
    /// Cache of servers with the machServiceName as the key.
    ///
    /// This exists for correctness reasons, not as a performance optimization. Only one connection for a named service can exist simultaneously, so it's important
    /// this invariant be upheld when returning `XPCServer` instances.
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
                let cachedRequirementsData = Set<Data>(try cachedServer.clientRequirements.map(requirementTransform))
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

	public override func start() -> Never {
        // Attempts to bind to the Mach service. If this isn't actually a Mach service a EXC_BAD_INSTRUCTION will occur.
        let machService = machServiceName.withCString { serviceNamePointer in
            return xpc_connection_create_mach_service(
                serviceNamePointer,
                nil, // targetq: DispatchQueue, defaults to using DISPATCH_TARGET_QUEUE_DEFAULT
                UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
        }
        
		// Start listener for the Mach service, all received events should be for incoming connections
		 xpc_connection_set_event_handler(machService, { connection in
			 // Listen for events (messages or errors) coming from this connection
			 xpc_connection_set_event_handler(connection, { event in
				 self.handleEvent(connection: connection, event: event)
			 })
			 xpc_connection_resume(connection)
		 })
		 xpc_connection_resume(machService)

        // Park the main thread, allowing for incoming connections and requests to be processed
        dispatchMain()
	}

	internal override func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
		// Get the code representing the client
		var code: SecCode?
		if #available(macOS 11, *) { // publicly documented, but only available since macOS 11
			SecCodeCreateWithXPCMessage(message, SecCSFlags(), &code)
		} else { // private undocumented function: xpc_connection_get_audit_token, available on prior versions of macOS
			if var auditToken = xpc_connection_get_audit_token(connection) {
				let tokenData = NSData(bytes: &auditToken, length: MemoryLayout.size(ofValue: auditToken))
				let attributes = [kSecGuestAttributeAudit : tokenData] as NSDictionary
				SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
			}
		}

		// Accept message if code is valid and meets any of the client requirements
		var accept = false
		if let code = code {
			for requirement in self.clientRequirements {
				if SecCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess {
					accept = true
				}
			}
		}

		return accept
	}

	/// Wrapper around the private undocumented function `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)`.
	///
	/// The private undocumented function will attempt to be dynamically loaded and then invoked. If no function exists with this name `nil` will be returned. If
	/// the function does exist, but does not match the expected signature, the process calling this function is expected to crash. However, because this is only
	/// called on older versions of macOS which are expected to have a stable non-changing API this is very unlikely to occur.
	///
	/// - Parameters:
	///   - _:  The connection for which the audit token will be retrieved for.
	/// - Returns: The audit token or `nil` if the function could not be called.
	private func xpc_connection_get_audit_token(_ connection: xpc_connection_t) -> audit_token_t? {
		typealias functionSignature = @convention(c) (xpc_connection_t, UnsafeMutablePointer<audit_token_t>) -> Void
		let auditToken: audit_token_t?

		// Attempt to dynamically load the function
		if let handle = dlopen(nil, RTLD_LAZY) {
			defer { dlclose(handle) }
			if let sym = dlsym(handle, "xpc_connection_get_audit_token") {
				let function = unsafeBitCast(sym, to: functionSignature.self)

				// Call the function
				var token = audit_token_t()
				function(connection, &token)
				auditToken = token
			} else {
				auditToken = nil
			}
		} else {
			auditToken = nil
		}

		return auditToken
	}
}

extension XPCMachServer: CustomDebugStringConvertible {
    
    /// Description which includes the name of the service and its memory address (to help in debugging uniqueness bugs)
    var debugDescription: String {
        "\(XPCMachServer.self) [\(self.machServiceName)] \(Unmanaged.passUnretained(self).toOpaque())"
    }
}
