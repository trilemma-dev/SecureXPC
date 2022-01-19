# ``SecureXPC``

A **secure** high-level XPC framework with [`Codable`](https://developer.apple.com/documentation/swift/codable)
compatability.

## Overview

SecureXPC provides an easy way to perform secure XPC communication with pure Swift. `Codable` conforming types are used
to make requests and receive responses. This framework can be used to communicate with any type of XPC Service or XPC
Mach service. Customized support for communicating with helper tools installed via 
[`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) is also provided.

## Usage
The envisioned pattern when using this framework is to define routes in a shared file, retrieve a server in one program
(such as a helper tool) and register these routes, then from another program (such as an app) retrieve a client and call
these routes.

#### Routes

In a file shared by the client and server define one or more routes:
```swift
let route = XPCRouteWithMessageWithReply("bedazzle",
                                         messageType: String.self,
                                         replyType: Bool.self)
```
There are four different types of routes; learn more about <doc:/Routes>.

#### Server

In one program retrieve a server, register those routes, and then start the server:
```swift
    ...
    let server = <# server retrieval here #>
    server.registerRoute(route, handler: bedazzle)
    server.start()
}

private func bedazzle(message: String) throws -> Bool {
     <# implementation here #>
}
```

See ``XPCServer`` for details on how to retrieve, configure, and start a server.

#### Client

In another program retrieve a client, then call one of those routes:
```swift
let client = <# client retrieval here #>
try client.sendMessage("Get Schwifty", route: route, withResponse: { response in
    switch response {
        case .success(let reply):
            <# use the reply #>
        case .failure(let error):
            <# handle the error #>
    }
})
```
See ``XPCClient`` for more on how to retrieve a client and send requests.

## Topics
### Client and Server
- ``XPCClient``
- ``XPCServer``

### Routes
- <doc:/Routes>
- ``XPCRouteWithoutMessageWithoutReply``
- ``XPCRouteWithMessageWithoutReply``
- ``XPCRouteWithoutMessageWithReply``
- ``XPCRouteWithMessageWithReply``

### Errors
- ``XPCError``
