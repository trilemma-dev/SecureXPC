//
//  PartialResult.swift
//  SecureXPC
//
//  Created by Josh Kaplan on 2022-03-31.
//

public enum PartialResult<Success, Failure> where Failure: Error {
    
    public struct PartialResultFinishedError: Error {
        fileprivate init() { }
    }
    
    case success(Success)
    case failure(Failure)
    case finished
    
    func get() throws -> Success {
        switch self {
            case .success(let success):
                return success
            case .failure(let failure):
                throw failure
            case .finished:
                throw PartialResultFinishedError()
        }
    }
}

extension PartialResult: Equatable where Success: Equatable, Failure: Equatable { }

extension PartialResult: Hashable where Success: Hashable, Failure: Hashable { }

extension PartialResult: Sendable where Success: Sendable, Failure: Sendable { }
