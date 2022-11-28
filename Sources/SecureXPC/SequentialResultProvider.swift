//
//  SequentialResultProvider.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-04-04.
//

import Foundation

/// Sends sequential responses to an ``XPCClient`` for a specific route.
///
/// Instances of this class are provided to handlers registered with an ``XPCServer`` for routes with sequential reply types:
/// - Async without a message — ``XPCServer/registerRoute(_:handler:)-6sxby``
/// - Async with a message — ``XPCServer/registerRoute(_:handler:)-7ngxn``
/// - Synchronous without a message — ``XPCServer/registerRoute(_:handler:)-7r1hv``
/// - Synchronous with a message — ``XPCServer/registerRoute(_:handler:)-qcox``
///
/// It is valid to use an instance of this class outside of the closure it was provided to. Responses will be sent so long as the client remains connected and the
/// sequence has not already been finished.
///
/// Any errors generated while using this provider will be passed to the ``XPCServer``'s error handler.
///
/// All results sent to the client including finishing a sequence are enqueued and sent asynchronously. For example a call to ``success(value:onDelivery:)``
/// may return before the result has actually been sent. To determine whether the client has actually received the result either call the `async` version such as
/// ``success(value:)`` or pass a ``SequentialResultDeliveryHandler`` to  ``success(value:onDelivery:)``. This can be particularly
/// useful in applying back pressure to the system to prevent the client from accumulating too many yet to be processed results. However, if this behavior is not
/// needed then do not use the `async` versions as `await`ing them will always wait on client delivery (unless an error occurs).
///
/// Once a sequence has been either explicitly finished or finishes because of an encoding error, any subsequent operations will not be sent and
/// ``XPCError/sequenceFinished`` will be passed to the error handler. If a sequence was not already finished, it will be finished upon deinitialization of this
/// provider instance.
///
/// While provider instances are thread-safe, attempting concurrent responses may lead to inconsistent ordering on the client side. If exact ordering is necessary, it is
/// recommended that callers synchronize access to a provider instance.
///
/// ## Topics
/// ### Responding with Optional Closures
/// - ``respond(withResult:onDelivery:)``
/// - ``success(value:onDelivery:)``
/// ### Finishing with Optional Closures
/// - ``finished(onDelivery:)``
/// - ``failure(error:onDelivery:)``
/// ### Delivery Closure
/// - ``SequentialResultDeliveryHandler``
/// ### Responding with Async
/// - ``respond(withResult:)``
/// - ``success(value:)``
/// ### Finishing with Async
/// - ``finished()``
/// - ``failure(error:)``
/// ### State
/// - ``isFinished``
public class SequentialResultProvider<S: Encodable> {
    private let request: Request
    private weak var server: XPCServer?
    private weak var connection: xpc_connection_t?
    private let serialQueue: DispatchQueue
    
    /// Invoked upon delivery of a result to a client, or failure to do so.
    ///
    /// If the result was not delivered successfully, the associated error will be provided to this handler. The error will also be provided to the ``XPCServer``'s
    /// error handler.
    public typealias SequentialResultDeliveryHandler = (Result<Void, XPCError>) -> Void
    
    /// Whether this provider has finished replying with results.
    ///
    /// Once a provider is finished, calling any of its functions will result in ``XPCError/sequenceFinished`` and the response not being sent.
    ///
    /// This will be `true` if ``finished(onDelivery:)`` or ``failure(error:onDelivery:)`` have been called or
    /// ``respond(withResult:onDelivery:)`` was passed ``SequentialResult/finished`` or ``SequentialResult/failure(_:)``.
    /// However, this will not necessarily be `true` immediately after one of those functions return as finishing a sequence is processed asynchronously.
    public private(set) var isFinished: Bool
    
    init(request: Request, server: XPCServer, connection: xpc_connection_t) {
        self.request = request
        self.server = server
        self.connection = connection
        self.isFinished = false
        self.serialQueue = DispatchQueue(label: "response-provider-\(request.requestID)")
    }
    
    /// Finishes the sequence if it hasn't already been.
    deinit {
        // There's no need to run this on the serial queue as deinit does not run concurrently with anything else
        if !self.isFinished, let connection = connection {
            // This intentionally doesn't call finished() because that would run async and by the time it ran
            // deinitialization may have (and in practice typically will have) already completed
            do {
                var response = xpc_dictionary_create(nil, nil, 0)
                try Response.encodeRequestID(self.request.requestID, intoReply: &response)
                xpc_connection_send_message(connection, response)
            } catch {
                self.sendToServerErrorHandler(error)
                
                // There's no point trying to send the encoding error to the client because encoding the requestID
                // failed and that's needed by the client in order to properly reassociate the error with the request
            }
            
            self.endTransaction()
        }
    }
    
    /// Responds to the client with the provided result.
    ///
    /// - Parameters:
    ///   -   result: The sequential result to respond with.
    ///   -   deliveryHandler: Invoked upon succesful delivery of the result to the client or failure to do so.
    public func respond(
        withResult result: SequentialResult<S, Error>,
        onDelivery deliveryHandler: SequentialResultDeliveryHandler? = nil
    ) {
        switch result {
            case .success(let value):
                self.success(value: value, onDelivery: deliveryHandler)
            case .failure(let error):
                self.failure(error: error, onDelivery: deliveryHandler)
            case .finished:
                self.finished()
        }
    }
    
    /// Responds to the client with the provided result and waits for it to be handled.
    ///
    /// - Parameters:
    ///   -   result: The sequential result to respond with.
    @available(macOS 10.15, *)
    public func respond(withResult result: SequentialResult<S, Error>) async throws {
        try await withUnsafeThrowingContinuation { continuation in
            self.respond(withResult: result) { continuation.resume(with: $0) }
        }
    }
    
    /// Responds to the client with the provided value.
    ///
    /// - Parameters:
    ///   -   value: The value to be sent.
    ///   -   deliveryHandler: Invoked upon succesful delivery of the value to the client or failure to do so.
    public func success(value: S, onDelivery deliveryHandler: SequentialResultDeliveryHandler? = nil) {
        self.sendResponse(isFinished: false, onDelivery: deliveryHandler) { response in
            try Response.encodePayload(value, intoReply: &response)
        }
    }
    
    /// Responds to the client with the provided value and waits for it to be handled.
    /// 
    /// This is equivalent to ``success(value:onDelivery:)`` and providing a ``SequentialResultDeliveryHandler`` meaning that awaiting this
    /// function call will wait on the client to have handled the value provided to this function. If there is no need to wait on the client (for example in order to rate
    /// limit sending new sequential reply values) then use ``success(value:onDelivery:)`` and pass `nil` for the delivery handler.
    ///
    /// - Parameters:
    ///   -   value: The value to be sent.
    @available(macOS 10.15, *)
    public func success(value: S) async throws {
        try await withUnsafeThrowingContinuation { continuation in
            self.success(value: value) { continuation.resume(with: $0) }
        }
    }
    
    /// Responds to the client with the error and finishes the sequence.
    ///
    /// This error will also be passed to the ``XPCServer``'s error handler if one has been set.
    ///
    /// - Parameters:
    ///   -   error: The error to be sent to the client and passed to the server's error handler.
    ///   -   deliveryHandler: Invoked upon succesful delivery of the error to the client or failure to do so.
    public func failure(error: Error, onDelivery deliveryHandler: SequentialResultDeliveryHandler? = nil) {
        let handlerError = HandlerError(error: error)
        self.sendToServerErrorHandler(handlerError)
        
        self.sendResponse(isFinished: true, onDelivery: deliveryHandler) { response in
            try Response.encodeError(XPCError.handlerError(handlerError), intoReply: &response)
        }
    }
    
    /// Responds to the client with the error, finishes the sequence, and waits for it to be handled.
    ///
    /// This error will also be passed to the ``XPCServer``'s error handler if one has been set.
    ///
    /// This is equivalent to ``failure(error:onDelivery:)`` and providing a ``SequentialResultDeliveryHandler`` meaning that awaiting this
    /// function call will wait on the client to have handled the error provided to this function.
    ///
    /// - Parameters:
    ///   -   error: The error to be sent to the client and passed to the server's error handler.
    @available(macOS 10.15, *)
    public func failure(error: Error) async throws {
        try await withUnsafeThrowingContinuation { continuation in
            self.failure(error: error) { continuation.resume(with: $0) }
        }
    }
    
    /// Responds to the client indicating the sequence is finished.
    ///
    /// If a sequence was not already finished, it will be finished upon deinitialization of this provider.
    ///
    /// - Parameters:
    ///   -   deliveryHandler: Invoked upon succesful completion of the sequence on the client side or failure to do so.
    public func finished(onDelivery deliveryHandler: SequentialResultDeliveryHandler? = nil) {
        // An "empty" response indicates it's finished
        self.sendResponse(isFinished: true, onDelivery: deliveryHandler) { _ in }
    }
    
    /// Responds to the client indicating the sequence is finished and waits for it to be handled.
    ///
    /// If a sequence was not already finished, it will be finished upon deinitialization of this provider.
    ///
    /// This is equivalent to ``finished(onDelivery:)`` and providing a ``SequentialResultDeliveryHandler`` meaning that awaiting this
    /// function call will wait on the client to have handled the sequence finishing.
    @available(macOS 10.15, *)
    public func finished() async throws {
        try await withUnsafeThrowingContinuation { continuation in
            self.finished() { continuation.resume(with: $0) }
        }
    }
    
    private func sendResponse(
        isFinished: Bool,
        onDelivery deliveryHandler: SequentialResultDeliveryHandler?,
        encodingWork: @escaping (inout xpc_object_t) throws -> Void
    ) {
        self.serialQueue.async {
            if self.isFinished {
                deliveryHandler?(.failure(XPCError.sequenceFinished))
                self.sendToServerErrorHandler(XPCError.sequenceFinished)
                return
            }
            
            self.isFinished = isFinished
            
            guard let connection = self.connection else {
                deliveryHandler?(.failure(XPCError.clientNotConnected))
                self.sendToServerErrorHandler(XPCError.clientNotConnected)
                return
            }

            do {
                var response = xpc_dictionary_create(nil, nil, 0)
                try Response.encodeRequestID(self.request.requestID, intoReply: &response)
                
                do {
                    try encodingWork(&response)
                    if let deliveryHandler = deliveryHandler {
                        xpc_connection_send_message_with_reply(connection, response, nil) { _ in
                            deliveryHandler(.success(()))
                        }
                    } else {
                        xpc_connection_send_message(connection, response)
                    }
                } catch {
                    deliveryHandler?(.failure(XPCError.asXPCError(error: error)))
                    self.sendToServerErrorHandler(error)
                    
                    do {
                        let errorResponse = xpc_dictionary_create(nil, nil, 0)
                        try Response.encodeRequestID(self.request.requestID, intoReply: &response)
                        try Response.encodeError(XPCError.asXPCError(error: error), intoReply: &response)
                        xpc_connection_send_message(connection, errorResponse)
                        self.isFinished = true
                    } catch {
                        // Unable to send back the error, so there's nothing more to be done
                    }
                }
            } catch {
                // If we're not able to encode the requestID, there's no point sending back a response as the client
                // wouldn't be able to make use of it
                deliveryHandler?(.failure(XPCError.asXPCError(error: error)))
                self.sendToServerErrorHandler(error)
            }
            
            if isFinished {
                self.endTransaction()
            }
        }
    }
    
    private func sendToServerErrorHandler(_ error: Error) {
        if let server = server {
            server.errorHandler.handle(XPCError.asXPCError(error: error))
        }
    }
    
    /// Sends an empty reply to the client such that it ends the transaction
    private func endTransaction() {
        if let connection = connection {
            guard let reply = xpc_dictionary_create_reply(self.request.dictionary) else {
                fatalError("Unable to create reply for request \(request.requestID)")
            }
            xpc_connection_send_message(connection, reply)
        }
    }
}
