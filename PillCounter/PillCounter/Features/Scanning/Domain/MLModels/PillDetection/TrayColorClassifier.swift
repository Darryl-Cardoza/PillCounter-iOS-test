// TrayColorClassifier.swift
// PillCounter
//
// Native, dependency-free generic-color classifier for the counting tray.
//
// Used by the hazardous-tray feature: the first time a tray is detected during
// a scan, we sample the average colour of the tray region from the raw camera
// CVPixelBuffer and map it to one of a small set of generic colours (red, blue,
// gray, white, …). That generic name is what gets stored / compared — we
// intentionally keep this coarse, not a strict colour match.
//
// No third-party libraries are used: pixels are read directly from the BGRA
// buffer and classified in HSV space.

import Foundation
import CoreVideo
import CoreGraphics

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Generic tray colours
// ─────────────────────────────────────────────────────────────────────────────

/// A coarse, generic colour bucket for a tray. Deliberately not exhaustive —
/// just the common physical tray colours an operator would recognise.
enum TrayColor: String, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray, white, black

    /// User-facing, capitalised name used in popups / toasts and persisted in storage.
    var displayName: String { rawValue.capitalized }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Classifier
// ─────────────────────────────────────────────────────────────────────────────

enum TrayColorClassifier {

    /// Samples the average colour inside `rect` of `pixelBuffer` and maps it to a
    /// generic `TrayColor`.
    ///
    /// - Parameters:
    ///   - pixelBuffer: a `kCVPixelFormatType_32BGRA` frame (the camera's raw buffer).
    ///   - rect: the tray region in **raw camera-buffer pixel coordinates** — the
    ///           same coordinate space as `TrayResult.rect`, so no transform is needed.
    /// - Returns: the classified colour, or `nil` if the rect is empty / the buffer
    ///            can't be read.
    static func dominantColor(in pixelBuffer: CVPixelBuffer, rect: CGRect) -> TrayColor? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Clamp the sample region to the buffer bounds.
        let minX = max(0, Int(rect.minX))
        let minY = max(0, Int(rect.minY))
        let maxX = min(width  - 1, Int(rect.maxX))
        let maxY = min(height - 1, Int(rect.maxY))
        guard maxX > minX, maxY > minY else { return nil }

        // Sample a coarse grid (~20×20) so this stays cheap regardless of tray size.
        let stepX = max(1, (maxX - minX) / 20)
        let stepY = max(1, (maxY - minY) / 20)

        var sumR = 0, sumG = 0, sumB = 0, count = 0
        var y = minY
        while y <= maxY {
            let rowOffset = y * bytesPerRow
            var x = minX
            while x <= maxX {
                let p = rowOffset + x * 4   // BGRA
                sumB += Int(ptr[p + 0])
                sumG += Int(ptr[p + 1])
                sumR += Int(ptr[p + 2])
                count += 1
                x += stepX
            }
            y += stepY
        }
        guard count > 0 else { return nil }

        let r = Double(sumR) / Double(count) / 255.0
        let g = Double(sumG) / Double(count) / 255.0
        let b = Double(sumB) / Double(count) / 255.0

        return classify(r: r, g: g, b: b)
    }

    /// Maps a normalised (0–1) RGB triple to a generic colour via HSV bucketing.
    private static func classify(r: Double, g: Double, b: Double) -> TrayColor {
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let delta = maxV - minV

        let value = maxV                              // brightness
        let saturation = maxV == 0 ? 0 : delta / maxV

        // Achromatic: decide white / gray / black by brightness.
        if saturation < 0.18 {
            if value > 0.75 { return .white }
            if value < 0.22 { return .black }
            return .gray
        }

        // Very dark colours read as black regardless of hue.
        if value < 0.16 { return .black }

        // Hue in degrees (0–360).
        var hue: Double = 0
        if delta != 0 {
            if maxV == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxV == g {
                hue = 60 * (((b - r) / delta) + 2)
            } else {
                hue = 60 * (((r - g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }

        switch hue {
        case ..<15:           return .red
        case ..<45:           return .orange
        case ..<70:           return .yellow
        case ..<170:          return .green
        case ..<255:          return .blue
        case ..<290:          return .purple
        case ..<335:          return .pink
        default:              return .red   // 335–360 wraps back to red
        }
    }
}
