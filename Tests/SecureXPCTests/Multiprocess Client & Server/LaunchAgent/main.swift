//
//  main.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-23
//

import Foundation
import SecureXPC

let server = try createServer()

server.registerRoute(SharedRoutes.echoRoute) { $0 }

var latestAndGreatest = LatestAndGreatest(now: CFAbsoluteTimeGetCurrent(), latestValue: Double.random(in: 0.0...1000.0))
server.registerRoute(SharedRoutes.latestRoute) { latestAndGreatest }
server.registerRoute(SharedRoutes.mutateLatestRoute) {
    latestAndGreatest.now = CFAbsoluteTimeGetCurrent()
    latestAndGreatest.latestValue += Double.random(in: 0.0...1000.0)
}

server.startAndBlock()

func createServer() throws -> XPCServer {
    // To simplify things while having a dynamically generated Mach service name, the name is the name of this executable
    let machServiceName = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent

    // This is a useless security requirement which essentially allows any client to connect, unless it happens to have
    // an Info.plist entry called `VeryUnlikelyThisWouldEverExist`
    var requirement: SecRequirement?
    SecRequirementCreateWithString("!info [VeryUnlikelyThisWouldEverExist] exists" as CFString, [], &requirement)
    let criteria = XPCServer.MachServiceCriteria(machServiceName: machServiceName,
                                                 clientRequirement: .secRequirement(requirement!))

    return try XPCServer.forMachService(withCriteria: criteria)
}
