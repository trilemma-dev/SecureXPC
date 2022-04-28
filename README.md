Use pure Swift to easily and securely communicate with XPC services and XPC Mach services. A client-server model 
enables you to use your own [`Codable`](https://developer.apple.com/documentation/swift/codable) conforming types to
send requests to routes you define and receive responses. 

SecureXPC uses [Swift concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html) on macOS 10.15 and
later allowing clients to make non-blocking asynchronous requests to servers. A closure-based API is also available
providing compatibility back to OS X 10.10.

This framework is ideal for communicating with helper tools installed via 
[`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) and login items installed
via
[`SMLoginItemSetEnabled`](https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled).
It's built with security in mind, minimizing the opportunities for 
[exploits](https://objectivebythesea.com/v3/talks/OBTS_v3_wReguła.pdf). Server-side security checks are performed
against the actual calling process instead of relying on PIDs which are known to be
[insecure](https://saelo.github.io/presentations/warcon18_dont_trust_the_pid.pdf).

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftrilemma-dev%2FSecureXPC%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/trilemma-dev/SecureXPC)

# Usage
The envisioned pattern when using this framework is to define routes in a shared file, create a server in one program
(such as a helper tool) and register these routes, then from another program (such as an app) create a client and send
requests to these routes.

## Routes
In a file shared by the client and server define one or more routes:
```swift
let route = XPCRoute.named("bedazzle")
                    .withMessageType(String.self)
                    .withReplyType(Bool.self)
```

## Server
In one program retrieve a server, register those routes, and then start the server:
```swift
    ...
    let server = <# server retrieval here #>
    server.registerRoute(route, handler: bedazzle)
    server.startAndBlock()
}

private func bedazzle(message: String) throws -> Bool {
     <# implementation here #>
}
```

On macOS 10.15 and later `async` functions and closures can also be registered as the handler for a route.

There are multiple types of servers which can be retrieved:
 - `XPCServer.forThisXPCService()`
     - For an XPC service, which is a private helper tool available only to the main application that contains it
 - `XPCServer.forThisBlessedHelperTool()`
     - For a helper tool installed via
       [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless)
     - To see a sample app for this use case, check out
       [SwiftAuthorizationSample](https://github.com/trilemma-dev/SwiftAuthorizationSample)
 - `XPCServer.forThisLoginItem()`
     - For a login item installed with
       [`SMLoginItemSetEnabled`](https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled)
 - `XPCServer.forThisMachService(named:clientRequirements:)`
     - For
       [Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
       as well as more advanced `SMJobBless` helper tool configurations
 - `XPCServer.makeAnonymous()`
     - Typically used for testing purposes
 - `XPCServer.makeAnonymous(clientRequirements:)`
     - Enables applications not managed by `launchd` to communicate with each other, see documentation for more details

## Client
In another program retrieve a client, then send a request to a registered route:
```swift
let client = <# client retrieval here #>
let reply = try await client.sendMessage("Get Schwifty", to: route)
```

Closure-based variants are available for macOS 10.14 and earlier:
```swift
let client = <# client retrieval here #>
client.sendMessage("Get Schwifty", to: route, withResponse: { result in
    switch result {
        case .success(let reply):
            <# use the reply #>
        case .failure(let error):
            <# handle the error #>
    }
})
```

There are multiple types of clients which can be retrieved:
 - `XPCClient.forXPCService(named:)`
     - For communicating with an XPC service
     - This corresponds to servers created with `XPCServer.forThisXPCService()`
 - `XPCClient.forMachService(named:)`
     - For communicating with an XPC Mach service
     - This corresponds to servers created with `XPCServer.forThisBlessedHelperTool()`,
       `XPCServer.forThisLoginItem()`, and
       `XPCServer.forThisMachService(named:clientRequirements:)`
 - `XPCClient.forEndpoint(_:)`
    - This is the only way to communicate with an anonymous server
    - This corresponds to servers created with `XPCServer.makeAnonymous()` or
      `XPCServer.makeAnonymous(clientRequirements:)`
    - It can also be used with an XPC Mach service

---

# `Codable` vs `NSSecureCoding`
SecureXPC uses types conforming to Swift's `Codable` protocol to serialize data across the XPC connection. Due to the
nature of how `Codable` is defined, it is not possible for the same instance to be referenced from multiple other
deserialized instances. This is in contrast to how
[`NSSecureCoding`](https://developer.apple.com/documentation/foundation/nssecurecoding) behaves, which is used by
[`NSXPCConnection`](https://developer.apple.com/documentation/foundation/nsxpcconnection) for serialization.

While there are considerable similarities between these two serialization protocols, there is a significant difference
in how deserialization occurs. A `Codable` conforming type is always decoded via its
[initializer](https://developer.apple.com/documentation/swift/decodable/2894081-init) with no possibility of
substitution. In contrast, an `NSSecureCoding` conforming type may use
[`awakeAfter(using:)`](https://developer.apple.com/documentation/objectivec/nsobject/1417074-awakeafter) to substitute
in an already initialized instance.

While `Codable` can be implemented by any type, in practice value types such as `struct` and `enum` are the most natural
fit. The aforementioned deserialization behavior is by definition not applicable to value types.
