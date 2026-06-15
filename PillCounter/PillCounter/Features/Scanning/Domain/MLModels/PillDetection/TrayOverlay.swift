// TrayOverlay.swift
// PillCounter
//
// Draws a rounded-rectangle overlay for TRAY regions detected by
// TrayDetectionService.
//
// Coordinate conversion uses AVCaptureVideoPreviewLayer.layerRectConverted,
// the same approach DetectionOverlay (pill dots) uses. AVFoundation maps the
// normalized metadata rect into layer space correctly for BOTH portrait and
// landscape, accounting for the active video orientation and resizeAspectFill
// crop. The previous manual math was hardcoded for the portrait 90° CW
// rotation and therefore misaligned the tray box in landscape.

import AVFoundation
import SwiftUI

struct TrayOverlay: View {

    @ObservedObject var cameraService: CameraService

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                if let layer = cameraService.previewLayer,
                   layer.session != nil {

                    ForEach(cameraService.trayDetections.filter { $0.trayClass == .tray }) { tray in
                        let screenRect = getScreenRect(for: tray, using: layer)

                        if screenRect.width > 0, screenRect.height > 0 {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.shared.secondary, lineWidth: 2)
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

    /// Maps a TrayResult bounding box to layer (screen) space using AVFoundation's
    /// layerRectConverted — orientation-aware, so it works in portrait and landscape.
    /// Draws exactly the model's box (same conversion the pill dots use); no clamp,
    /// no smoothing, no forced adjustment.
    private func getScreenRect(for tray: TrayResult,
                               using layer: AVCaptureVideoPreviewLayer) -> CGRect {

        let normalizedRect = CGRect(
            x: tray.rect.origin.x / tray.originalFrameSize.width,
            y: tray.rect.origin.y / tray.originalFrameSize.height,
            width: tray.rect.width / tray.originalFrameSize.width,
            height: tray.rect.height / tray.originalFrameSize.height
        )

        return layer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
    }
}
