//
//  XPCServiceServer.swift
//  SecureXPC
//
//  Created by Alexander Momchilov on 2021-11-07
//

import Foundation

/// A concrete implementation of ``XPCServer`` which acts as a server for an XPC Service.
///
/// In the case of this framework, the XPC Service is expected to be communicated with by an `XPCServiceClient`.
internal class XPCServiceServer: XPCServer {
    
	private static let service = XPCServiceServer()

    internal static func _forThisXPCService() throws -> XPCServiceServer {
        // An XPC Service's package type must be equal to "XPC!", see Apple's documentation for details
        // https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW6
        if mainBundlePackageInfo().packageType != "XPC!" {
            throw XPCError.notXPCService
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
            xpc_connection_set_target_queue(connection, XPCServiceServer.service.targetQueue)
			// Listen for events (messages or errors) coming from this connection
			xpc_connection_set_event_handler(connection, { event in
				XPCServiceServer.service.handleEvent(connection: connection, event: event)
			})
            XPCServiceServer.service.addConnection(connection)
			xpc_connection_resume(connection)
		}
	}

	internal override func acceptMessage(connection: xpc_connection_t, message: xpc_object_t) -> Bool {
		// XPC services are application-scoped, so we're assuming they're inheritently safe
		true
	}
}
