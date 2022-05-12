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
	private static let service = XPCServiceServer(messageAcceptor: AlwaysAcceptingMessageAcceptor())
    
    internal static func _forThisXPCService() throws -> XPCServiceServer {
        // An XPC service's package type must be equal to "XPC!", see Apple's documentation for details
        // https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW6
        if mainBundlePackageInfo().packageType != "XPC!" {
            throw XPCError.notXPCService
        }

        if Bundle.main.bundleIdentifier == nil {
            throw XPCError.misconfiguredXPCService(description: "The bundle identifier is missing; XPC services " +
                                                                "must have one")
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
}
