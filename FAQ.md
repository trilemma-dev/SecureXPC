# Why should I use SecureXPC instead of Apple's frameworks?
Apple provides two XPC frameworks, their [XPC C framework](https://developer.apple.com/documentation/xpc) and their
[Objective-C framework](https://developer.apple.com/documentation/foundation/xpc) which is often referred to as the 
`NSXPCConnection` API.

## Write idiomatic Swift
While both can be used from Swift via its language bridging functionality, doing so requires significant non-idiomatic
Swift usage throughout much of the codebase that it touches. For example to use `NSXPCConnection` requires that all data
transferred over the XPC connection be annotated with `@objc`, conform to `NSSecureCoding` and be a `class` - `struct`s
are not supported. Usage of the C API requires considerable manual boxing and unboxing of data types and with unsafe
access required to transfer types such as string.

## It's secure
Mach services are by default accessible to any other non-sandboxed process on the system. This can (and often has\*)
resulted in serious security vulnerabilities. This is rather obviously true for services running as root such as those
installed with `SMJobBless`, but is also applicable for even sandboxed Mach services such as a login item which has been
granted permissions to system resources such as the user's microphone or camera.

SecureXPC automatically validates incoming connections for many types of common services such as those installed with
`SMJobBless` and login items. For those not automatically supported, a simple declarative API allows for specifying
client requirements such as only allowing connections from clients with the same team identifier. If desired
requirements can be fully customized via Apple's
[code signing requirement language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html).

\*There are so many documented cases of these types of security vulnerabilities that it'd be hard to list them all out,
but here are a few:
- [Don't Trust the PID!](https://saelo.github.io/presentations/warcon18_dont_trust_the_pid.pdf)
- [Exploiting XPC in AntiVirus Software](https://youtu.be/zQlE7AzgGdI)
- [OSX XPC Revisited - 3rd Party Application Flaws](https://youtu.be/KPzhTqwf0bA)
- [Abusing & Security XPC in macOS apps](https://youtu.be/ezxD5M90Mmc)

## It's simple
XPC is very powerful, but it can also be very arcane. SecureXPC offers a simple yet powerful client server API. This is
done by supporting most common scenarios while excluding a few less common ones. For example it takes just a few lines
of code for your app to asynchronously call your server and get back a reponse. Only a little bit more code is needed
for your client to receive an `AsyncThrowingStream` which can be populated on demand by the server as needed.

This simplicity is achieved in a few key ways:
- Full Swift concurrency (`async` and `await`) means there's no need to use handlers and closures
- Bidirectional functionality is exposed as an `AsyncThrowingStream` instead of adhoc function calls
- Routing is built into SecureXPC, you don't have to roll your own solution as you would when using the C API
- Security is automatic

# What are the differences between `Codable` vs `NSSecureCoding`?
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

# My app and/or service is sandboxed, can I use SecureXPC?
Absolutely. However, Apple places extensive restrictions on a sandboxed process's ability to establish XPC connections.
An app may always communicate a bundled XPC service, but cannot establish a connection to an XPC Mach service.

# Can SecureXPC allow my sandboxed app to talk to an XPC Mach service?
Yes, so long as you're able and willing to create a non-sandboxed XPC service. Non-sandboxed XPC services are able to
create connections to the XPC Mach services. At a high level this looks like:

XPC Mach service:
- Registers a route which returns its endpoint.

Non-sandboxed XPC service:
- Creates a client which connects to the XPC Mach service.
- Registers a route which returns the XPC Mach services endpoint. To do this registered handler uses the client to call
  the XPC Mach service's route which returns its endpoint.
  
Sandboxed app:
- Creates a client which connects to the non-sandboxed XPC service.
- Calls the non-sandboxed XPC service's route to retrive the endpoint for the XPC Mach service.
- Create a client using the retrieved endpoint.

The above is possible using either the closure-based functions or the Swift concurrency ones, but it will be _much_
simpler to do so using Swift concurrency.

# Can I use SecureXPC in a Mac App Store app?
I don't know. If you've succesfully published a Mac App Store app with SecureXPC, please start a GitHub discussion to
let me know.

SecureXPC makes use of the private API `xpc_connection_get_audit_token` on macOS 10.15 and earlier (a public equivalent
exists starting with macOS 11). I can imagine this might result in an app store rejection.
