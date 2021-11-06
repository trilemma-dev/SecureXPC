# Routes

Client to server communication is facilitated by defining routes. A route is a sequence of `String`s and if applicable
also the message and reply types.

In practice a route is similar to a function signature or a server path with type safety, although it is not precisely
either. Message and reply types must be 
[`Codable`](https://developer.apple.com/documentation/swift/codable). Many structs, enums, and classes in the Swift
standard library are already `Codable` and compiler generated conformance is available for simple structs and enums.

The simplest form of a route is one that contains neither a message nor a reply:
```swift
let resetRoute = XPCRouteWithoutMessageWithoutReply("reset")
```

In many cases a reply will be desired, for example to know if the operation succeeded:
```swift
let throttleThermalRoute = XPCRouteWithoutMessageWithReply("thermal", "throttle",
                                                           replyType: Bool.self)
```

Routes can have a message sent to them that don't have a reply:
```swift
let limitThermalRoute = XPCRouteWithMessageWithoutReply("thermal", "limit",
                                                        messageType: Int.self)
```

As well as those that do expect a reply:
```swift
let isLimitSafeRoute = XPCRouteWithMessageWithoutReply("thermal", "limit",
                                                       messageType: Int.self,
                                                       replyType: Bool.self)
```

Routes are distinct based on their paths, message type, and reply type meaning that the last two routes here are
distinct because the penultimate one does not have a reply type while the last one has a reply type of `Bool`.

#### Storing Routes
To ensure consistency, ideally routes are only defined once in code that is shared by both your client and server.

#### Updating Routes
Take care when updating existing routes because over time you may end up with an older version of your server installed
on a computer with a newer client.

#### Registering Routes
See ``XPCMachServer``.

#### Calling Routes
See ``XPCMachClient``.
