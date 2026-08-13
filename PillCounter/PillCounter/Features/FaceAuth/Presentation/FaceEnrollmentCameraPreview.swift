//
//  FaceEnrollmentCameraPreview.swift
//  PillCounter
//
//  Thin AVCaptureVideoPreviewLayer wrapper for the enrollment screen. Mirrors
//  Features/Scanning's CameraView/PreviewView shape.
//

import AVFoundation
import SwiftUI
import UIKit

struct FaceEnrollmentCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Physical camera currently feeding `session` — the preview layer's
    /// OWN connection (separate from AVCaptureVideoDataOutput's) needs the
    /// same front/back-mirrored videoOrientation fix, otherwise what the
    /// user visually sees stays rotated even though the ML-facing output
    /// connection is correct.
    var cameraPosition: AVCaptureDevice.Position = .front

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.applyOrientation(for: cameraPosition)
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.applyOrientation(for: cameraPosition)
    }

    final class PreviewLayerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }

        /// Matches FaceEnrollmentCameraService.applyConnectionOrientation —
        /// same fixed-orientation-per-idiom rule (portrait on iPhone,
        /// landscape on iPad, front/back sensors mirrored on iPad).
        func applyOrientation(for position: AVCaptureDevice.Position) {
            guard let connection = previewLayer.connection, connection.isVideoOrientationSupported else { return }
            if UIDevice.current.userInterfaceIdiom == .pad {
                connection.videoOrientation = position == .front ? .landscapeRight : .landscapeLeft
            } else {
                connection.videoOrientation = .portrait
            }
        }
    }
}
