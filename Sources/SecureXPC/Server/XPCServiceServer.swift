//
//  XPCServiceServer.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-07
//

import Foundation

/// A concrete implementation of ``XPCServer`` which acts as a server for an XPC service.
///
/// In the case of this framework, the XPC service is expected to be communicated with by an `XPCServiceClient`.
internal class XPCServiceServer: XPCServer {
    
    
    internal static var isThisProcessAnXPCService: Bool {
        mainBundlePackageInfo().packageType == "XPC!"
    }
    
	private static let service = XPCServiceServer(messageAcceptor: AlwaysAcceptingMessageAcceptor())
    
    internal static func _forThisXPCService() throws -> XPCServiceServer {
        // An XPC service's package type must be equal to "XPC!", see Apple's documentation for details
        // https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW6
        
        guard mainBundlePackageInfo().packageType == "XPC!" else {
            throw XPCError.misconfiguredServer(description: "An XPC service's CFBundlePackageType value must be XPC!")
       }

        if Bundle.main.bundleIdentifier == nil {
            throw XPCError.misconfiguredServer(description: "An XPC service must have a CFBundleIdentifier")
        }
        
        return service
    }
    
    /// Returns a bundle’s package type and creator.
    private static func mainBundlePackageInfo() -> (packageType: String?, packageCreator: String?) {
        var packageType = UInt32()
        var packageCreator = UInt32()
        CFBundleGetPackageInfo(CFBundleGetMainBundle(), &packageType, &packageCreator)

        func uint32ToString(_ input: UInt32) -> String? {
            if input == 0 {
                return nil
            }
            var input = input
            return String(data: Data(bytes: &input, count: MemoryLayout<UInt32>.size), encoding: .utf8)
        }

        return (uint32ToString(packageType.bigEndian), uint32ToString(packageCreator.bigEndian))
    }

    public override func startAndBlock() -> Never {
        xpc_main { connection in
            // This is a @convention(c) closure, so we can't just capture `self`.
            // As such, the singleton reference `XPCServiceServer.service` is used instead.
            XPCServiceServer.service.startClientConnection(connection)
        }
    }

    public override var connectionDescriptor: XPCConnectionDescriptor {
        // This is safe to unwrap because it was already checked in `_forThisXPCService()`.
        let serviceName = Bundle.main.bundleIdentifier!
        
        return .xpcService(name: serviceName)
    }
    
    public override var endpoint: XPCServerEndpoint? {
        // An `XPCServiceServer` can't have an endpoint created for it. From a technical perspective this is because
        // endpoints are only created from connection listeners, which an XPC service doesn't expose (incoming
        // connections are simply passed to the handler provided to `xpc_main(...)`. From a security point of view, it
        // makes sense that it's not possible to create an endpoint for an XPC service because they're designed to only
        // allow communication between the main app and .xpc bundles contained within the same main app's bundle. As
        // such there's no valid use case for creating such an endpoint.
        nil
    }
}
