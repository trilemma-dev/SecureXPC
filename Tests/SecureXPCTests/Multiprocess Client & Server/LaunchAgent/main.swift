//
//  main.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-23
//

import Foundation
import SecureXPC

// This code runs as a launch agent, which is created by LaunchAgent.swift.
// Make sure to only reference SecureXPC and Shared.swift; anything else will fail when compiling.

let server = try createServer()

server.registerRoute(SharedRoutes.echoRoute) { $0 }

var latestAndGreatest = LatestAndGreatest(now: SharedTrivial(CFAbsoluteTimeGetCurrent()),
                                          latestValue: SharedTrivial(Double.random(in: 0.0...1000.0)))
server.registerRoute(SharedRoutes.latestRoute) { latestAndGreatest }
server.registerRoute(SharedRoutes.mutateLatestRoute) {
    try latestAndGreatest.now.updateValue(CFAbsoluteTimeGetCurrent())
    let nextValue = try latestAndGreatest.latestValue.retrieveValue() + Double.random(in: 0.0...1000.0)
    try latestAndGreatest.latestValue.updateValue(nextValue)
}

server.registerRoute(SharedRoutes.terminate) {
    exit(0)
}
server.registerRoute(SharedRoutes.fibonacciRoute) { n, provider in
    fibonacciSequence(n: n, provider: provider)
    provider.finished()
}

server.registerRoute(SharedRoutes.selfTerminatingFibonacciRoute) { n, provider in
    fibonacciSequence(n: n, provider: provider)
    provider.finished { _ in
        exit(0)
    }
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

func fibonacciSequence(n: UInt, provider: SequentialResultProvider<UInt>) {
    let artificialDelay = 0.001
    
    if n >= 1 {
        provider.success(value: 0)
        Thread.sleep(forTimeInterval: artificialDelay)
    }
    
    if n >= 2 {
        provider.success(value: 1)
        Thread.sleep(forTimeInterval: artificialDelay)
    }
    
    if n >= 3 {
        var prev: UInt = 0
        var current: UInt = 1
        
        for _ in 2..<n {
            let lastCurrent = current
            current = current + prev
            prev = lastCurrent
            provider.success(value: current)
            Thread.sleep(forTimeInterval: artificialDelay)
        }
    }
}
