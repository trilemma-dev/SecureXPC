SecureXPC provides an easy way to perform secure XPC Mach service communication. 
[`Codable`](https://developer.apple.com/documentation/swift/codable) conforming types are used to send messages and
receive replies. This framework is ideal for communicating with helper tools installed via 
[`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless).

To see a runnable sample app using this framework, check out
[SwiftAuthorizationSample](https://github.com/trilemma-dev/SwiftAuthorizationSample).

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftrilemma-dev%2FSecureXPC%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/trilemma-dev/SecureXPC)

# Usage
The envisioned pattern when using this framework is to define routes in a shared file, create a server in one program
(such as a helper tool) and register these routes, then from another program (such as an app) create a client and call
these routes.

## Routes
In a file shared by the client and server define one or more routes:
```swift
let route = XPCRouteWithMessageWithReply("bezaddle",
                                         messageType: String.self,
                                         replyType: Bool.self)
```

## Server
In one program create a server, register those routes, and then start the server:
```swift
    ...
    let server = XPCMachServer(machServiceName: "com.example.service",
                               clientRequirements: requirements)
    server.registerRoute(route, handler: bedazzle)
    server.start()
}

private func bedazzle(message: String) throws -> Bool {
     <# implementation here #>
}
```

If this program is a helper tool installed by `SMJobBless`, then in many cases it can be initialized automatically:
```swift
let server = XPCMachServer.forThisBlessedHelperTool()
```

## Client
In another program create a client, then call one of those routes:
```swift
let client = XPCMachClient(machServiceName: "com.example.service")
try client.sendMessage("Get Schwifty", route: route, withReply: { result in
    switch result {
        case let .success(reply):
            <# use the reply #>
        case let .failure(error):
            <# handle the error #>
    }
})
```

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
