//
//  NSRegularExpression+Safe.swift
//  PillCounter
//

import Foundation

extension NSRegularExpression {

    /// Compiles a static, hardcoded pattern without `try!`. These patterns are
    /// compile-time constants today (never crash), but a future typo edit to one
    /// would otherwise take down the whole app on first use — this logs and falls
    /// back to a pattern that never matches instead.
    static func literal(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            AppLogger.shared.error("NSRegularExpression: invalid literal pattern '\(pattern)', falling back to a never-matching pattern", error: error, event: .unknownError)
            // "$^" is a fixed, guaranteed-valid pattern that matches nothing.
            return try! NSRegularExpression(pattern: "$^")
        }
    }
}
