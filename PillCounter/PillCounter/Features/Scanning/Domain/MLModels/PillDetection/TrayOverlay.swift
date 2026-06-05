// TrayOverlay.swift
// PillCounter
//
// Draws a rounded-rectangle overlay for TRAY regions detected by
// TrayDetectionService.
//
// Coordinate conversion is computed manually in the GeometryReader's
// coordinate space (which matches the full-screen SwiftUI layout) rather
// than using layerRectConverted, which operates in UIKit layer space and
// can introduce a small origin offset when bridged through UIViewRepresentable.
//
// Camera delivers landscape frames (e.g. 1504×1128).
// Portrait display rotates them 90° CW with resizeAspectFill:
//   landscape x-axis (left→right) → portrait y-axis (top→bottom)
//   landscape y-axis (top→bottom) → portrait x-axis (right→left, with crop)

import AVFoundation
import SwiftUI

struct TrayOverlay: View {

    @ObservedObject var cameraService: CameraService

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let layer = cameraService.previewLayer,
                   layer.session != nil {

                    let _ = debugLayerVsGeo(layer: layer, geo: geo.size)

                    ForEach(cameraService.trayDetections.filter { $0.trayClass == .tray }) { tray in
                        let screenRect = portraitRect(for: tray, in: geo.size)

                        if screenRect != .zero {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 0, green: 0.784, blue: 0.325), lineWidth: 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(red: 0, green: 0.784, blue: 0.325).opacity(0.13))
                                )
                                .frame(width: screenRect.width,
                                       height: screenRect.height)
                                .position(x: screenRect.midX,
                                          y: screenRect.midY)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate Conversion

    /// Maps a TrayResult bounding box to the GeometryReader's SwiftUI coordinate
    /// space for portrait display.
    ///
    /// The camera delivers a landscape pixel buffer (fw × fh).
    /// In portrait the frame is rotated 90° CW and aspect-filled to (sw × sh):
    ///   scale  = sh / fw          (portrait height filled by landscape width)
    ///   cropX  = (fh·scale − sw) / 2   (horizontal crop from each side)
    ///
    ///   screen_y = nx · sh
    ///   screen_h = nw · sh
    ///   screen_x = (1 − ny − nh) · fh · scale − cropX
    ///   screen_w = nh · fh · scale
    private func portraitRect(for tray: TrayResult, in containerSize: CGSize) -> CGRect {
        let fw = tray.originalFrameSize.width
        let fh = tray.originalFrameSize.height
        let sw = containerSize.width
        let sh = containerSize.height

        let frameBounds = CGRect(origin: .zero, size: tray.originalFrameSize)
        let clamped = tray.rect.intersection(frameBounds)
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return .zero }

        let scale = sh / fw
        let scaledFH = fh * scale
        let cropX = max(0, (scaledFH - sw) / 2)

        let nx = clamped.minX / fw
        let ny = clamped.minY / fh
        let nw = clamped.width / fw
        let nh = clamped.height / fh

        let screenY = nx * sh
        let screenH = nw * sh
        let screenX = (1 - ny - nh) * scaledFH - cropX
        let screenW = nh * scaledFH

        let result = CGRect(x: screenX, y: screenY, width: screenW, height: screenH)

        print(String(format:
            "── [TRAY OVERLAY] norm=(%.3f,%.3f,%.3f×%.3f) → screen=(%.0f,%.0f,%.0f×%.0f) container=(%.0f×%.0f)",
            nx, ny, nw, nh,
            result.origin.x, result.origin.y, result.width, result.height,
            sw, sh))

        return result
    }

    /// Prints layer bounds vs GeometryReader size once per render so any
    /// UIKit/SwiftUI origin mismatch is visible in the console.
    @discardableResult
    private func debugLayerVsGeo(layer: AVCaptureVideoPreviewLayer, geo: CGSize) -> Bool {
        print(String(format:
            "── [TRAY OVERLAY] layerBounds=(%.0f×%.0f) geoSize=(%.0f×%.0f)",
            layer.bounds.width, layer.bounds.height, geo.width, geo.height))
        return true
    }
}
