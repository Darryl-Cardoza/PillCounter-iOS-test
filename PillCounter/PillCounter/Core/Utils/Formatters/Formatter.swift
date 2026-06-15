//
//  Formatter.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import Foundation

struct Formatter {
    static func maskEmail(_ email: String) -> String {
        // Split email into username and domain
        let components = email.split(separator: "@")
        guard components.count == 2 else { return email }  // invalid email, return as-is

        let username = String(components[0])
        let domain = String(components[1])

        // Show first two characters, mask the rest (but ensure at least one mask)
        let visibleCount = min(2, username.count)
        let visiblePart = String(username.prefix(visibleCount))
        let maskedPart = String(
            repeating: "*", count: max(username.count - visibleCount, 1))

        return "\(visiblePart)\(maskedPart)@\(domain)"
    }
    
    // MARK: - Date & Time Formatting
    
    /// Returns date string (e.g., "18 Nov 2025")
    static func getDateString(from timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }
    
    /// Returns time string (e.g., "04:30 PM")
    static func getTimeString(from timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
    }
    
    /// Splits a full name into first and last name
    /// - Parameter fullName: The full name string
    /// - Returns: Tuple containing firstName and lastName
    static func segregateName(from fullName: String) -> (firstName: String, lastName: String) {

        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return ("", "")
        }

        let components = trimmed.split(separator: " ", maxSplits: 1)

        let firstName = String(components.first ?? "")
        let lastName = components.count > 1 ? String(components[1]) : ""

        return (firstName, lastName)
    }
}
