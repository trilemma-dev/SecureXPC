//
//  XPCMachServer.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2021-10-09
//

import Foundation

/// An XPC Mach Services server to receive calls from and send responses to ``XPCMachClient``.
///
/// ### Creating a Server
/// If the program creating this server is a helper tool which meets
/// [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) requirements then in most
/// cases creating a server is as easy as
/// ```swift
/// let server = try XPCMachServer.forBlessedHelperTool()
/// ```
/// See ``forBlessedHelperTool()`` for the exact requirements which need to be met.
///
/// **Other Cases**
///
/// Otherwise you'll need to manually initialize a server by specifying the name of the XPC Mach Service and providing the security requirements for connecting
/// clients. See ``init(machServiceName:clientRequirements:)`` for an example and details.
///
/// **Requirement Checking**
///
/// On macOS 11 and later, requirement checking uses publicly documented APIs. On older versions of macOS, the private undocumented API
/// `void xpc_connection_get_audit_token(xpc_connection_t, audit_token_t *)` will be used; if for some reason the function is unavailable
/// then no messages will be accepted. When messages are not accepted, if the ``XPCMachServer/errorHandler`` is set then it is called
/// with ``XPCError/insecure``.
///
/// ### Registering & Handling Routes
/// Once a server instance has been created, one or more routes should be registered with it. This is done by calling one
/// of the `registerRoute` functions and providing a route and a compatible closure or function. For example:
/// ```swift
///     ...
///     let updateConfigRoute = XPCRouteWithMessageWithReply("update", "config",
///                                                          messageType:Config.self,
///                                                          replyType: Config.self)
///     server.registerRoute(updateConfigRoute, handler: updateConfig)
/// }
///
/// private func updateConfig(_ config: Config) throws -> Config {
///     <# implementation here #>
/// }
/// ```
///
/// If the function or closure provided as the `handler` parameter throws an error and the route expects a return, then
/// ``XPCError/remote(_:)`` will be returned to the client with the `String` associated type describing the thrown error. It
/// is intentional the thrown error is not marshalled as that type may not be `Codable` and may not exist in the client.
///
/// ### Starting a Server
/// Once all of the routes are registered, the server must be told to start processing requests:
/// ```swift
/// server.start()
/// ```
///
/// This function replicates default [`xpc_main()`](https://developer.apple.com/documentation/xpc/1505740-xpc_main)
/// behavior by calling [`dispatchMain()`](https://developer.apple.com/documentation/dispatch/1452860-dispatchmain) and
/// never returning.
///
/// ## Topics
/// ### Creating a Server
/// - ``forBlessedHelperTool()``
/// - ``init(machServiceName:clientRequirements:)``
///
/// ### Registering Routes
/// - ``registerRoute(_:handler:)-8ydqa``
/// - ``registerRoute(_:handler:)-76t5b``
/// - ``registerRoute(_:handler:)-39dgn``
/// - ``registerRoute(_:handler:)-1rnkw``
///
/// ### Starting a Server
/// - ``start()``
///
/// ### Error Handling
/// - ``errorHandler``
public class XPCMachServer {
    
    /// If set, errors encountered will be sent to this handler.
    public var errorHandler: ((XPCError) -> Void)?
    
    private let machService: xpc_connection_t
    private let clientRequirements: [SecRequirement]
    
    // Routes
    private var routesWithoutMessageWithReply = [XPCRoute : XPCHandlerWithoutMessageWithReply]()
    private var routesWithMessageWithReply = [XPCRoute : XPCHandlerWithMessageWithReply]()
    private var routesWithoutMessageWithoutReply = [XPCRoute : XPCHandlerWithoutMessageWithoutReply]()
    private var routesWithMessageWithoutReply = [XPCRoute : XPCHandlerWithMessageWithoutReply]()
    
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
            return xpc_connection_create_mach_service(serviceNamePointer,
                                                      nil,
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
        let launchdPropertyList = try PropertyListSerialization.propertyList(from: launchdData,
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
        let infoPropertyList = try PropertyListSerialization.propertyList(from: infoData,
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
    
    /// Registers a route that has no message and can't receive a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths and types.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute(_ route: XPCRouteWithoutMessageWithoutReply,
                              handler: @escaping () throws -> Void) {
        let handlerWrapper = ConstrainedXPCHandlerWithoutMessageWithoutReply(handler: handler)
        self.routesWithoutMessageWithoutReply[route.route] = handlerWrapper
    }
    
    /// Registers a route that has a message and can't receive a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths and types.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and can't receive a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<M: Decodable>(_ route: XPCRouteWithMessageWithoutReply<M>,
                                            handler: @escaping (M) throws -> Void) {
        let handlerWrapper = ConstrainedXPCHandlerWithMessageWithoutReply(handler: handler)
        self.routesWithMessageWithoutReply[route.route] = handlerWrapper
    }
    
    /// Registers a route that has no message and expects a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths and types.
    ///
    /// - Parameters:
    ///   - route: A route that has no message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<R: Decodable>(_ route: XPCRouteWithoutMessageWithReply<R>,
                                            handler: @escaping () throws -> R) {
        let handlerWrapper = ConstrainedXPCHandlerWithoutMessageWithReply(handler: handler)
        self.routesWithoutMessageWithReply[route.route] = handlerWrapper
    }
    
    /// Registers a route that has a message and expects a reply.
    ///
    /// If this route has already been registered, calling this function will overwrite the existing registration. Routes are unique based on their paths and types.
    ///
    /// - Parameters:
    ///   - route: A route that has a message and expects a reply.
    ///   - handler: Will be called when the server receives an incoming request for this route if the request is accepted.
    public func registerRoute<M: Decodable, R: Encodable>(_ route: XPCRouteWithMessageWithReply<M, R>,
                                                          handler: @escaping (M) throws -> R) {
        let handlerWrapper = ConstrainedXPCHandlerWithMessageWithReply(handler: handler)
        self.routesWithMessageWithReply[route.route] = handlerWrapper
    }
    
    /// Begins processing requests received by this XPC server.
    ///
    /// This function replicates [`xpc_main()`](https://developer.apple.com/documentation/xpc/1505740-xpc_main) behavior by never
    /// returning.
    public func start() -> Never {
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
    
    private func handleEvent(connection: xpc_connection_t, event: xpc_object_t) {
        if xpc_get_type(event) == XPC_TYPE_DICTIONARY {
            if self.acceptMessage(connection: connection, message: event) {
                var reply = xpc_dictionary_create_reply(event)
                do {
                    try handleMessage(connection: connection, message: event, reply: &reply)
                } catch let error as XPCError {
                    self.errorHandler?(error)
                    self.replyWithErrorIfPossible(error, connection: connection, reply: &reply)
                } catch let error as DecodingError {
                    self.errorHandler?(XPCError.decodingError(error))
                    self.replyWithErrorIfPossible(error, connection: connection, reply: &reply)
                }  catch let error as EncodingError {
                    self.errorHandler?(XPCError.encodingError(error))
                    self.replyWithErrorIfPossible(error, connection: connection, reply: &reply)
                } catch {
                    self.errorHandler?(XPCError.other(error))
                    self.replyWithErrorIfPossible(error, connection: connection, reply: &reply)
                }
            } else {
                self.errorHandler?(XPCError.insecure)
            }
        } else if xpc_equal(event, XPC_ERROR_CONNECTION_INVALID) {
            self.errorHandler?(XPCError.connectionInvalid)
        } else if xpc_equal(event, XPC_ERROR_CONNECTION_INTERRUPTED) {
            self.errorHandler?(XPCError.connectionInterrupted)
        } else if xpc_equal(event, XPC_ERROR_TERMINATION_IMMINENT) {
            self.errorHandler?(XPCError.terminationImminent)
        } else {
            self.errorHandler?(XPCError.unknown)
        }
    }
    
    /// Determines whether the message should be accepted.
    ///
    /// This is determined using the client requirements provided to this server upon initialization.
    /// - Parameters:
    ///   - connection: The connection the message was sent over.
    ///   - message: The message.
    /// - Returns: whether the message can be accepted
    private func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
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
    
    private func handleMessage(connection: xpc_connection_t, message: xpc_object_t, reply: inout xpc_object_t?) throws {
        let route = try XPCDecoder.decodeRoute(message)
        let containsPayload = try XPCDecoder.containsPayload(message)
        
        // If a dictionary reply exists, then the message expects a reply
        if var reply = reply {
            if containsPayload {
                if let handler = self.routesWithMessageWithReply[route] {
                    try handler.handle(message: message, reply: &reply)
                    xpc_connection_send_message(connection, reply)
                } else {
                    throw XPCError.routeNotRegistered(String(describing: route))
                }
            } else {
                if let handler = self.routesWithoutMessageWithReply[route] {
                    try handler.handle(reply: &reply)
                    xpc_connection_send_message(connection, reply)
                } else {
                    throw XPCError.routeNotRegistered(String(describing: route))
                }
            }
        } else { // Otherwise the message can't receive a reply
            if containsPayload {
                if let handler = self.routesWithMessageWithoutReply[route] {
                    try handler.handle(message: message)
                } else {
                    throw XPCError.routeNotRegistered(String(describing: route))
                }
            } else {
                if let handler = self.routesWithoutMessageWithoutReply[route] {
                    try handler.handle()
                } else {
                    throw XPCError.routeNotRegistered(String(describing: route))
                }
            }
        }
    }
    
    private func replyWithErrorIfPossible(_ error: Error, connection: xpc_connection_t, reply: inout xpc_object_t?) {
        if var reply = reply {
            do {
                try XPCEncoder.encodeError(error, forReply: &reply)
                xpc_connection_send_message(connection, reply)
            } catch {
                // If encoding the error fails, then there's no way to proceed
            }
        }
    }
}

// MARK: handler function wrappers

// These wrappers perform type erasure via their implemented protocols while internally maintaining type constraints
// This makes it possible to create heterogenous collections of them

fileprivate protocol XPCHandlerWithoutMessageWithoutReply {
    func handle() throws -> Void
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithoutReply: XPCHandlerWithoutMessageWithoutReply {
    let handler: () throws -> Void
    
    func handle() throws {
        try self.handler()
    }
}

fileprivate protocol XPCHandlerWithMessageWithoutReply {
    func handle(message: xpc_object_t) throws -> Void
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithoutReply<M: Decodable>: XPCHandlerWithMessageWithoutReply {
    let handler: (M) throws -> Void
    
    func handle(message: xpc_object_t) throws {
        let decodedMessage = try XPCDecoder.decodePayload(message, asType: M.self)
        try self.handler(decodedMessage)
    }
}

fileprivate protocol XPCHandlerWithoutMessageWithReply {
    func handle(reply: inout xpc_object_t) throws
}

fileprivate struct ConstrainedXPCHandlerWithoutMessageWithReply<R: Encodable>: XPCHandlerWithoutMessageWithReply {
    let handler: () throws -> R
    
    func handle(reply: inout xpc_object_t) throws {
        let encodedReply = try self.handler()
        try XPCEncoder.encodeReply(&reply, value: encodedReply)
    }
}

fileprivate protocol XPCHandlerWithMessageWithReply {
    func handle(message: xpc_object_t, reply: inout xpc_object_t) throws
}

fileprivate struct ConstrainedXPCHandlerWithMessageWithReply<M: Decodable, R: Encodable>: XPCHandlerWithMessageWithReply {
    let handler: (M) throws -> R
    
    func handle(message: xpc_object_t, reply: inout xpc_object_t) throws {
        let decodedMessage = try XPCDecoder.decodePayload(message, asType: M.self)
        let encodedReply = try self.handler(decodedMessage)
        try XPCEncoder.encodeReply(&reply, value: encodedReply)
    }
}
