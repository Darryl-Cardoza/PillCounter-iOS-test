//
//  TrayOverlay.swift
//  PillCounter
//
//  Created by Bhushan Patil on 18/03/26.
//

import AVFoundation
import SwiftUI

/// Draws a rounded-rectangle overlay for every detected tray.
/// Coordinate conversion is identical to DetectionOverlay — uses
/// AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:).
struct TrayOverlay: View {

    @ObservedObject var cameraService: CameraService
    @EnvironmentObject var appColors: AppColors

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                if let layer = cameraService.previewLayer,
                   layer.session != nil {

                    ForEach(cameraService.trayDetections) { tray in
                        let screenRect = layerRect(for: tray, layer: layer)

                        RoundedRectangle(cornerRadius: 8)
                            .stroke(appColors.secondary, lineWidth: 2)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(appColors.secondary.opacity(0.08))
                            )
                            .frame(width: screenRect.width,
                                   height: screenRect.height)
                            .position(x: screenRect.midX,
                                      y: screenRect.midY)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate conversion (same logic as DetectionOverlay)

    private func layerRect(for tray: TrayResult,
                           layer: AVCaptureVideoPreviewLayer) -> CGRect {
        let normalised = CGRect(
            x: tray.rect.origin.x / tray.originalFrameSize.width,
            y: tray.rect.origin.y / tray.originalFrameSize.height,
            width:  tray.rect.width  / tray.originalFrameSize.width,
            height: tray.rect.height / tray.originalFrameSize.height
        )
        return layer.layerRectConverted(fromMetadataOutputRect: normalised)
    }
}
