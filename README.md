Use pure Swift to easily communicate with XPC Services and XPC Mach services, with customized support for helper tools
installed via [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless). A
client-server model is used with [`Codable`](https://developer.apple.com/documentation/swift/codable) conforming types
to send messages and receive replies to registered routes.

macOS 10.10 and later is supported. Starting with macOS 10.15, clients can use `async` functions to make calls while
servers can register `async` handlers for their routes.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftrilemma-dev%2FSecureXPC%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/trilemma-dev/SecureXPC)

# Usage
The envisioned pattern when using this framework is to define routes in a shared file, create a server in one program
(such as a helper tool) and register these routes, then from another program (such as an app) create a client and call
these routes.

## Routes
In a file shared by the client and server define one or more routes:
```swift
let route = XPCRoute.named("bedazzle")
                    .withMessageType(String.self)
                    .withReplyType(Bool.self)
```

## Server
In one program create a server, register those routes, and then start the server:
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

There are multiple types of servers which can be retrieved:
 - `XPCServer.forThisXPCService()`
     - For an XPC Service, which is a private helper available only to the main application that contains it
 - `XPCServer.forThisBlessedHelperTool()`
     - For a helper tool installed via
       [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless)
     - To see a runnable sample app of this use case, check out
       [SwiftAuthorizationSample](https://github.com/trilemma-dev/SwiftAuthorizationSample)
 - `XPCServer.forThisMachService(named:clientRequirements:)`
     - For Launch Agents, Launch Daemons, and more advanced `SMJobBless` helper tool configurations
 - `XPCServer.makeAnonymous()`
     - Typically used for testing purposes
 - `XPCServer.makeAnonymous(clientRequirements:)`
     - Enables applications not managed by `launchd` to communicate with each other, see documentation for more details.

## Client
In another program create a client, then call one of those routes:
```swift
let client = <# client retrieval here #>
try client.sendMessage("Get Schwifty", route: route, withResponse: { result in
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
     - For communicating with an XPC Service
     - This corresponds to servers created with `XPCServer.forThisXPCService()`
 - `XPCClient.forMachService(named:)`
     - For communicating with an XPC Mach service
     - This corresponds to servers created with `XPCServer.forThisBlessedHelperTool()` or
       `XPCServer.forThisMachService(named:clientRequirements:)`
 - `XPCClient.forEndpoint(_:)`
    - This is the only way to communicate with an anonymous server
    - It can also be used with an XPC Mach service

---

# `Codable` vs `NSSecureCoding`
SecureXPC uses types conforming to Swift's `Codable` protocol to serialize data across the XPC connection. Due to the
nature of how `Codable` is defined, it is not possible for the same instance to be referenced from  multiple other
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
