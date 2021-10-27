SecureXPC provides an easy way to perform secure XPC Mach Services communication. 
[`Codable`](https://developer.apple.com/documentation/swift/codable) conforming types are used to send messages and
receive replies. This framework is ideal for communicating with helper tools installed via 
[`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless).

To see a runnable sample app using this framework, check out
[SwiftAuthorizationSample](https://github.com/trilemma-dev/SwiftAuthorizationSample).

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
let server = XPCMachServer.forBlessedHelperTool()
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
