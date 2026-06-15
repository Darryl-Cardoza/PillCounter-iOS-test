//
//  AppColors.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import SwiftUI

@MainActor
final class AppColors: ObservableObject {

    static let shared = AppColors()

    // MARK: - State
    @Published fileprivate(set) var colorScheme: AppColorScheme?
    @Published var isDarkMode: Bool = false

    private init(forceDark: Bool = false) { isDarkMode = forceDark }

    // MARK: - Public API

    /// Set color scheme from API response
    func update(with scheme: AppColorScheme?) {
        self.colorScheme = scheme
    }

    /// Called when system Light/Dark mode changes
    func updateSystemAppearance(_ isDark: Bool) {
        guard isDarkMode != isDark else { return }
        isDarkMode = isDark
    }

    // MARK: - Helpers

    private func hexColor(_ hex: String?, fallback: String) -> Color {
        Color(hex: hex ?? fallback)
    }

    private var currentPalette: AppColorPalette? {
        isDarkMode ? colorScheme?.dark : colorScheme?.light
    }

    // MARK: - Colors

    var primary: Color {
        hexColor(currentPalette?.primary, fallback: "01BBD3")
    }

    var secondary: Color {
        hexColor(currentPalette?.secondary, fallback: "FD82B5")
    }

    var tertiary: Color {
        let fallback = isDarkMode ? "FFFFFF" : "333333"
        return hexColor(currentPalette?.tertiary, fallback: fallback)
    }

    var primaryBackground: Color {
        let fallback = isDarkMode ? "333333" : "EDEEEE"
        return hexColor(currentPalette?.primaryBackground, fallback: fallback)
    }

    var secondaryBackground: Color {
        let fallback = isDarkMode ? "191919" : "FFFFFF"
        return hexColor(currentPalette?.secondaryBackground, fallback: fallback)
    }

    var text: Color {
        let fallback = isDarkMode ? "EDEEEE" : "666666"
        return hexColor(currentPalette?.textColor, fallback: fallback)
    }

    var inputBackground: Color {
        let fallback = isDarkMode ? "191919" : "FFFFFF"
        return hexColor(currentPalette?.inputBackground, fallback: fallback)
    }

    var statusChipBackgroundOnPrimary: Color {
        let fallback = isDarkMode ? "191919" : "FFFFFF"
        return hexColor(
            currentPalette?.statusChipBackgroundOnPrimary,
            fallback: fallback
        )
    }

    var statusChipBackgroundOnSecondary: Color {
        let fallback = isDarkMode ? "333333" : "F5F4F4"
        return hexColor(
            currentPalette?.statusChipBackgroundOnSecondary,
            fallback: fallback
        )
    }

    // MARK: - Dark-forced snapshot (for overlays that must always be dark)

    /// Returns a new AppColors instance with isDarkMode forced to true,
    /// sharing the same color scheme data. Use only as a scoped environmentObject.
    func forcedDark() -> AppColors {
        let copy = AppColors(forceDark: true)
        copy.colorScheme = self.colorScheme
        return copy
    }
}

