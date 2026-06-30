//
//  DosageFormIcon.swift
//  PillCounter
//
//  Created by Bhushan Patil on 24/06/26.
//

import Foundation

/// Maps a dosage form string to the corresponding asset icon name.
enum DosageFormIcon {

    /// Returns the asset icon name for the given dosage form string.
    /// - If the string contains "CAPSULE" -> `icon_dashboard_dispense`
    /// - If the string contains "TABLET"  -> `form_tablet`
    /// - Otherwise falls back to `form_tablet`.
    static func iconName(for dosageForm: String?) -> String {
        let form = (dosageForm ?? "").uppercased()

        if form.contains("CAPSULE") {
            return "form_capsule"
        } else if form.contains("TABLET") {
            return "form_tablet"
        }
        return "form_tablet"
    }
}
