Use pure Swift to easily and securely communicate with XPC services and XPC Mach services. A client-server model 
enables you to use your own [`Codable`](https://developer.apple.com/documentation/swift/codable) conforming types to
send requests to routes you define and receive responses. 

SecureXPC uses [Swift concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html) on macOS 10.15 and
later allowing clients to make non-blocking asynchronous requests to servers. A closure-based API is also available
providing compatibility back to OS X 10.10.

This framework can be used to communicate with any type of XPC service or Mach service, with customized support for:
- [XPC services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
- Helper tools installed using 
  [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless)
- Login items enabled with 
  [`SMLoginItemSetEnabled`](https://developer.apple.com/documentation/servicemanagement/1501557-smloginitemsetenabled)
- Daemons registered via 
  [`SMAppService.daemon(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/3945410-daemon)
- Agents registered via 
  [`SMAppService.agent(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/3945409-agent)

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
 - `XPCServer.forMachService()`
     - For agents and daemons registered with `SMAppService`, `SMJobBless` helper tools, and `SMLoginItemSetEnabled`
       login items
 - `XPCServer.forMachService(withCriteria:)`
     - For any type of Mach service including "classic" agents and daemons. See documentation for details
 - `XPCServer.makeAnonymous()`
     - Typically used for testing purposes
 - `XPCServer.makeAnonymous(withClientRequirements:)`
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

There are three types of clients which can be retrieved:
 - `XPCClient.forXPCService(named:)`
     - For communicating with an XPC service
     - This corresponds to servers created with `XPCServer.forThisXPCService()`
 - `forMachService(named:withServerRequirement:)`
     - For communicating with a Mach service
     - This corresponds to servers created with `XPCServer.forMachService()` or
       `XPCServer.forMachService(withCriteria:)`
 - `forEndpoint(_:withServerRequirement:)`
    - This is the only way to communicate with an anonymous server
    - This corresponds to servers created with `XPCServer.makeAnonymous()` or
      `XPCServer.makeAnonymous(withClientRequirements:)`
    - This type of client can also be used to communicate with any server via its `endpoint` property

---

# Questions you may have
See the [FAQ](FAQ.md) for answers to questions you may have or didn't even realize you wanted answered.
