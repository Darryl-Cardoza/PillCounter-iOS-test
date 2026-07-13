//
//  Hl7ParseFailureError.swift
//  PillCounter
//

import Foundation

/// Wraps an `HL7ParseResult.Failure` so it can be reported through
/// `Hl7EventListener.onError`, which expects a Swift `Error`.
struct Hl7ParseFailureError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}
