//
//  Validation.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import Foundation

struct Validation {

    /// Single source of truth for the email pattern, compiled once.
    private static let emailPattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
    private static let emailRegex = try? NSRegularExpression(pattern: emailPattern)

    /// Returns true if `value` is a syntactically valid email.
    private static func matchesEmail(_ value: String) -> Bool {
        guard let emailRegex else { return false }
        let range = NSRange(location: 0, length: value.utf16.count)
        return emailRegex.firstMatch(in: value, options: [], range: range) != nil
    }

    static func isValidEmail(_ email: String) -> Bool {
        matchesEmail(email)
    }

    static func validateEmail(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "EMAIL_ERROR_MESSAGE" }
        if !matchesEmail(trimmed) { return "EMAIL_ERROR_INVALID" }
        return nil
    }
}
