//
//  Shared.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-07-23
//

import Foundation
import SecureXPC

// This file is both compiled into the launch agent created by LaunchAgent.swift and referenced by main.swift as well as
// accessible from the SecureXPC tests - specificaly it's used in "LaunchAgent Tests.swift"

struct SharedRoutes {
    static let echoRoute = XPCRoute.named("echo")
                                   .withMessageType(String.self)
                                   .withReplyType(String.self)
    static let latestRoute = XPCRoute.named("retrieve", "latest")
                                     .withReplyType(LatestAndGreatest.self)
    static let mutateLatestRoute = XPCRoute.named("mutate", "latest")
    static let terminate = XPCRoute.named("terminate")
    static let fibonacciRoute = XPCRoute.named("fibonacci")
                                        .withMessageType(UInt.self)
                                        .withSequentialReplyType(UInt.self)
}

 struct LatestAndGreatest: Codable {
     let now: SharedTrivial<CFAbsoluteTime>
     let latestValue: SharedTrivial<Double>
 }
