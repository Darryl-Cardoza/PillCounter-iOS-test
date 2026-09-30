//
//  NSRegularExpression+Safe.swift
//  PillCounter
//

import Foundation

extension NSRegularExpression {

    /// Compiles a hardcoded pattern without `try!`; falls back to a never-matching one on a typo.
    static func literal(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            AppLogger.shared.error("NSRegularExpression: invalid literal pattern '\(pattern)', falling back to a never-matching pattern", error: error, event: .unknownError)
            return try! NSRegularExpression(pattern: "$^")
        }
    }
}
