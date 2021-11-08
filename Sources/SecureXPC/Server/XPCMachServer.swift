//
//  XPCMachServer.swift
//  
//
//  Created by Alexander Momchilov on 2021-11-08.
//

import Foundation

public class XPCMachServer: XPCServer {
	private let machService: xpc_connection_t
	private let clientRequirements: [SecRequirement]

	/// Creates a server that accepts requests from clients which meet the security requirements.
	///
	/// Because many processes on the system can talk to an XPC Mach Service, when creating a server it is required that you specifiy the security requirements
	/// of any connecting clients:
	/// ```swift
	/// let reqString = """identifier "com.example.AuthorizedClient" and certificate leaf[subject.OU] = "4L0ZG128MM" """
	/// var requirement: SecRequirement?
	/// if SecRequirementCreateWithString(reqString as CFString,
	///                                   SecCSFlags(),
	///                                   &requirement) == errSecSuccess,
	///   let requirement = requirement {
	///    let server = XPCMachServer(machServiceName: "com.example.service",
	///                               clientRequirements: [requirement])
	///
	///    <# configure and start server #>
	/// }
	/// ```
	///
	/// > Important: No requests will be processed until ``start()`` is called.
	///
	/// - Parameters:
	///   - machServiceName: The name of the mach service this server should bind to. This name must be present in this program's launchd property list's
	///                      `MachServices` entry.
	///   - clientRequirements: If a request is received from a client, it will only be processed if it meets one (or more) of these security requirements.
	public init(machServiceName: String, clientRequirements: [SecRequirement]) {
		self.clientRequirements = clientRequirements

		self.machService = machServiceName.withCString { serviceNamePointer in
			return xpc_connection_create_mach_service(
				serviceNamePointer,
				nil, // targetq: DispatchQueue, defaults to using DISPATCH_TARGET_QUEUE_DEFAULT
				UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
		}
	}

	/// Initializes a server for a helper tool that meets
	/// [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) requirements.
	///
	/// To successfully call this function the following requirements must be met:
	///   - The launchd property list embedded in this helper tool must have exactly one entry for its `MachServices` dictionary
	///   - The info property list embedded in this helper tool must have at least one element in its
	///   [`SMAuthorizedClients`](https://developer.apple.com/documentation/bundleresources/information_property_list/smauthorizedclients)
	///   array
	///   - Every element in the `SMAuthorizedClients` array must be a valid security requirement
	///     - To be valid, it must be creatable by
	///     [`SecRequirementCreateWithString`](https://developer.apple.com/documentation/security/1394522-secrequirementcreatewithstring)
	///
	/// Incoming requests will be accepted from clients that meet _any_ of the `SMAuthorizedClients` requirements.
	///
	/// > Important: No requests will be processed until ``start()`` is called.
	///
	/// - Returns: A server instance initialized with the embedded property list entries.
	public static func forBlessedHelperTool() throws -> XPCMachServer {
		// Determine mach service name launchd property list's MachServices
		var machServiceName: String
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

		return XPCMachServer(machServiceName: machServiceName, clientRequirements: clientRequirements)
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
		// Start listener for the mach service, all received events should be for incoming connections
		 xpc_connection_set_event_handler(self.machService, { connection in
			 // Listen for events (messages or errors) coming from this connection
			 xpc_connection_set_event_handler(connection, { event in
				 self.handleEvent(connection: connection, event: event)
			 })
			 xpc_connection_resume(connection)
		 })
		 xpc_connection_resume(self.machService)

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
