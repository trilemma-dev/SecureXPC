//
//  HandlerError.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-02-06
//

import Foundation

/// Represents an error thrown by a server's handler when processing a client's request.
public struct HandlerError: Error {
    /// The localized description of the underlying error.
    public let localizedDescription: String
    /// The error thrown by the handler.
    ///
    /// This error will always be present on the server; however, it will only exist on the client if it could be encoded by the server and decoded by the client.
    public let underlyingError: Error?
    /// The name of the underlying error's type within the server's runtime.
    ///
    /// Used to disambiguate enum case name conflicts when decoding.
    private let typeName: String
    
    private init(error: Error) {
        self.underlyingError = error
        self.localizedDescription = error.localizedDescription
        self.typeName = String(describing: type(of: error))
    }
    
    /// Wrap calls to an ``XPCServer``'s handlers in this.
    static func rethrow<T>(_ handler: () throws -> T) throws -> T {
        do {
            return try handler()
        } catch {
            throw HandlerError(error: error)
        }
    }
    
    /// Wrap calls to an ``XPCServer``'s `async` handlers in this.
    @available(macOS 10.15.0, *)
    static func rethrow<T>(_ handler: () async throws -> T) async throws -> T {
        do {
            return try await handler()
        } catch {
            throw HandlerError(error: error)
        }
    }
}

extension HandlerError: Codable {
    private enum CodingKeys: CodingKey {
        case localizedDescription
        case typeName
        case underlyingError
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.localizedDescription, forKey: .localizedDescription)
        try container.encode(self.typeName, forKey: .typeName)
        
        if let underlyingError = underlyingError as? Codable {
            // This is a bit hacky - we're "abusing" the ability to get a new encoder for a superclass and instead
            // using it to have the error encode itself
            let superEncoder = container.superEncoder(forKey: .underlyingError)
            try underlyingError.encode(to: superEncoder)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.localizedDescription = try container.decode(String.self, forKey: .localizedDescription)
        self.typeName = try container.decode(String.self, forKey: .typeName)
        
        // Attempt to decode the actual error; however, it may not have been encoded or it may not be possible on the
        // client to decode it (for example because we don't know what to decode it to)
        do {
            // This is the other side of the hacky coding we're doing to "abuse" the superclass encoder/decoder
            let superDecoder = try container.superDecoder(forKey: .underlyingError)
            guard let route = decoder.userInfo[XPCRoute.codingUserInfoKey] as? XPCRoute else {
                fatalError("Decoding process failed to add \(XPCRoute.self) to userInfo.")
            }
            
            // It's not that hard to end up with an error that could be decoded successfully as more than one type
            // of error (see tests for an example). This is because for enum based errors, the default encoding is
            // just the name of the case (and any associated values), so if the same case name exists in both enums
            // and they don't have an associated value (or the associated value types are the same) then it's valid
            // decoding.
            // To better handle this case, the name of the error's type will also be used to aide disambiguation.
            var decodedErrorsCount = 0
            var decodedErrors = [String : Error]()
            for errorType in route.errorTypes {
                do {
                    decodedErrors[String(describing: errorType)] = try errorType.init(from: superDecoder)
                    decodedErrorsCount += 1
                } catch { } // it's expected some decodings may fail
            }
            
            // Decoded errors for two or more errors that have the same type name, so can't know which one is correct
            if decodedErrorsCount != decodedErrors.count {
                self.underlyingError = nil
            } else if let error = decodedErrors[self.typeName] {
                self.underlyingError = error
            } else {
                self.underlyingError = nil
            }
        } catch {
            self.underlyingError = nil
        }
    }
}
