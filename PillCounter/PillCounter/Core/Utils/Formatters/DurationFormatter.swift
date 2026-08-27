//
//  DurationFormatter.swift
//  PillCounter
//

import Foundation

struct DurationFormatter {
    /// "Xh Ym remaining" style text for the offline-session hourglass badge.
    /// `nil` input (unknown remaining time) returns `nil` — caller should not show the badge.
    static func remainingTimeText(_ interval: TimeInterval?) -> String? {
        guard let interval, interval > 0 else { return nil }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: L10n.Offline.remainingTimeHoursMinutes, hours, minutes)
        } else if minutes > 0 {
            return String(format: L10n.Offline.remainingTimeMinutesOnly, minutes)
        } else {
            return L10n.Offline.remainingTimeLessThanMinute
        }
    }

    /// "HH:MM:SS" zero-padded countdown clock, e.g. "23:45:12".
    static func hhmmss(_ interval: TimeInterval?) -> String {
        guard let interval, interval > 0 else { return "00:00:00" }
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Full offline-logout-warning message with a live "HH:MM:SS" countdown, e.g.
    /// "Your internet has been disconnected. App will log out in 23:45:12".
    static func logoutWarningText(_ interval: TimeInterval?) -> String {
        String(format: L10n.Offline.logoutWarning, hhmmss(interval))
    }
}
