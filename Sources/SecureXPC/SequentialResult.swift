//
//  SequentialResult.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-03-31.
//

/// A value that represents a success, a failure, or completion of the sequence along with an associated value.
///
/// `SequentialResult` is similar to [`Result`](https://developer.apple.com/documentation/swift/result), but represents one of arbitrarily
/// many results that are returned in response to a request.
public enum SequentialResult<Success, Failure> where Failure: Error {
    
    public struct SequentialResultFinishedError: Error {
        fileprivate init() { }
    }
    
    /// This portion of the sequence was succesfully created and is available.
    case success(Success)
    /// The sequence has finished in failure, there will be no more results.
    case failure(Failure)
    /// The sequence has finished succesfully, there will be no more results.
    case finished
    
    func get() throws -> Success {
        switch self {
            case .success(let success):
                return success
            case .failure(let failure):
                throw failure
            case .finished:
                throw SequentialResultFinishedError()
        }
    }
}

extension SequentialResult: Equatable where Success: Equatable, Failure: Equatable { }

extension SequentialResult: Hashable where Success: Hashable, Failure: Hashable { }

extension SequentialResult: Sendable where Success: Sendable, Failure: Sendable { }
