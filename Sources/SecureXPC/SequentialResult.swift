//
//  SequentialResult.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-03-31.
//

/// A value that represents a success, a failure, or completion of the sequence.
///
/// `SequentialResult` is similar to [`Result`](https://developer.apple.com/documentation/swift/result), but represents one of arbitrarily
/// many results that are returned in response to a request.
///
/// ## Topics
/// ### Representing a Sequential Result
/// - ``success(_:)``
/// - ``failure(_:)``
/// - ``finished``
/// ### As a Throwing Expression
/// - ``get()``
/// - ``SequentialResultFinishedError``
public enum SequentialResult<Success, Failure> where Failure: Error {
    
    /// This portion of the sequence was succesfully created and is available.
    case success(Success)
    /// The sequence has finished in failure, there will be no more results.
    case failure(Failure)
    /// The sequence has finished succesfully, there will be no more results.
    case finished
    
    /// An error thrown when ``get()`` is called on a ``finished`` sequential result.
    public struct SequentialResultFinishedError: Error {
        fileprivate init() { }
    }
    
    /// Returns the success value as a throwing expression.
    ///
    /// If this represents ``finished`` then ``SequentialResultFinishedError`` will be thrown.
    public func get() throws -> Success {
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
