//
//  HandlerError.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-02-06
//

import Foundation

/// Represents an error thrown by a server's handler when processing a client's request.
public struct HandlerError: Error {
    
    /// Wrapper around the actual error thrown by the server or an explanation of why it is not available.
    public enum UnderlyingError {
        /// The underlying error is available and is the associated type of this case.
        ///
        /// This will always be the case on the server; however, on the client the other cases represented by this ``UnderlyingError`` may occur.
        case available(Error)
        /// The error was not encoded by the server and so there is no possibility of the client decoding it.
        case unavailableNotEncoded
        /// The error was encoded by the server, but the route had no error types specified which could decode it.
        case unavailableNoDecodingPossible
        /// The error was encoded by the server, but the route had multiple error types specified which could decode it.
        ///
        /// Because there were multiple types which could decode it, the client cannot know which one is valid.
        case unavailableMultipleDecodingsPossible
    }
    
    /// The localized description of the underlying error.
    public let localizedDescription: String
    /// Wrapper around the actual error thrown by the handler and whether it exists in this process.
    public let underlyingError: UnderlyingError
    /// The name of the underlying error's type within the server's runtime.
    ///
    /// Used to disambiguate enum case name conflicts when decoding.
    private let typeName: String
    
    private init(error: Error) {
        self.underlyingError = .available(error)
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
        
        if case let .available(underlyingError) = underlyingError,
           let underlyingError = underlyingError as? Codable {
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
        
        // This is the other side of the hacky coding we're doing to "abuse" the superclass encoder/decoder
        let superDecoder: Decoder
        do {
            superDecoder = try container.superDecoder(forKey: .underlyingError)
        } catch {
            self.underlyingError = .unavailableNotEncoded
            return
        }
        
        guard let route = decoder.userInfo[XPCRoute.codingUserInfoKey] as? XPCRoute else {
            fatalError("Decoding process failed to add \(XPCRoute.self) to userInfo.")
        }
        
        // It's not that hard to end up with an error that could be decoded successfully as more than one type of error
        // (see tests for an example). This is because for enum based errors, the default encoding is just the name of
        // the case (and any associated values), so if the same case name exists in both enums and they don't have an
        // associated value (or the associated value types are the same) then it's valid decoding.
        //
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
            self.underlyingError = .unavailableMultipleDecodingsPossible
        } else if let error = decodedErrors[self.typeName] {
            self.underlyingError = .available(error)
        } else {
            self.underlyingError = .unavailableNoDecodingPossible
        }
    }
}
