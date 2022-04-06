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
/// > Important: It is valid to use an instance of this class outside of the closure it was provided to. Responses will be sent so long as the client remains connected.
///
/// Any errors generated while using this provider will be passed to the ``XPCServer``'s error handler. Once a sequence has been either explicitly finished or
/// finishes because of an encoding error, any subsequent operations will not be sent and ``XPCError/sequenceFinished`` will be passed to the error handler.
///
/// While provider instances are thread-safe, attempting concurrent responses is likely to lead to inconsistent ordering on the client side. If exact ordering is
/// necessary, it is recommended that callers synchronize access to a provider instance.
///
/// ## Topics
/// ### Responding
/// - ``respond(withResult:)``
/// - ``success(value:)``
/// ### Finishing
/// - ``finished()``
/// - ``failure(error:)``
/// - ``isFinished``
public class SequentialResultProvider<S: Encodable> {
    private let requestID: UUID
    private weak var server: XPCServer?
    private weak var connection: xpc_connection_t?
    private let serialQueue: DispatchQueue
    
    /// Whether this provider has finished replying with results.
    ///
    /// Once a provider is finished, calling any of its functions will result in ``XPCError/sequenceFinished`` and the response not being sent.
    ///
    /// This will be `true` if ``finished()`` or ``failure(error:)`` have been called or ``respond(withResult:)`` was passed
    /// ``SequentialResult/finished`` or ``SequentialResult/failure(_:)``.
    public private(set) var isFinished: Bool
    
    init(request: Request, server: XPCServer, connection: xpc_connection_t) {
        self.requestID = request.requestID
        self.server = server
        self.connection = connection
        self.isFinished = false
        self.serialQueue = DispatchQueue(label: "response-provider-\(request.requestID)")
    }
    
    /// Responds to the client with the provided result.
    public func respond(withResult result: SequentialResult<S, Error>) {
        switch result {
            case .success(let value):
                self.success(value: value)
            case .failure(let error):
                self.failure(error: error)
            case .finished:
                self.finished()
        }
    }
    
    /// Responds to the client with the provided value.
    public func success(value: S) {
        self.sendResponse(isFinished: false) { response in
            try Response.encodePayload(value, intoReply: &response)
        }
    }
    
    /// Responds to the client with the provided error and finishes the sequence.
    ///
    /// This error will also be passed to the ``XPCServer``'s error handler if one has been set.
    public func failure(error: Error) {
        let handlerError = HandlerError(error: error)
        self.sendToServerErrorHandler(handlerError)
        
        self.sendResponse(isFinished: true) { response in
            try Response.encodeError(XPCError.handlerError(handlerError), intoReply: &response)
        }
    }
    
    /// Responds to the client indicating the sequence is now finished.
    public func finished() {
        // An "empty" response indicates it's finished
        self.sendResponse(isFinished: true) { _ in }
    }
    
    private func sendResponse(isFinished: Bool, encodingWork: @escaping (inout xpc_object_t) throws -> Void) {
        self.serialQueue.async {
            if self.isFinished {
                self.sendToServerErrorHandler(XPCError.sequenceFinished)
                return
            }
            
            self.isFinished = isFinished
            
            if let connection = self.connection {
                var response = xpc_dictionary_create(nil, nil, 0)
                do {
                    try Response.encodeRequestID(self.requestID, intoReply: &response)
                } catch {
                    // If we're not able to encode the requestID, there's no point sending back a response as the client
                    // wouldn't be able to make use of it
                    self.sendToServerErrorHandler(error)
                    return
                }
                
                do {
                    try encodingWork(&response)
                    xpc_connection_send_message(connection, response)
                } catch {
                    self.sendToServerErrorHandler(error)
                    
                    do {
                        let errorResponse = xpc_dictionary_create(nil, nil, 0)
                        try Response.encodeRequestID(self.requestID, intoReply: &response)
                        try Response.encodeError(XPCError.asXPCError(error: error), intoReply: &response)
                        xpc_connection_send_message(connection, errorResponse)
                        self.isFinished = true
                    } catch {
                        // Unable to send back the error, so just bail
                        return
                    }
                }
            } else {
                self.sendToServerErrorHandler(XPCError.clientNotConnected)
            }
        }
    }
    
    func sendToServerErrorHandler(_ error: Error) {
        if let server = server {
            server.errorHandler.handle(XPCError.asXPCError(error: error))
        }
    }
}
