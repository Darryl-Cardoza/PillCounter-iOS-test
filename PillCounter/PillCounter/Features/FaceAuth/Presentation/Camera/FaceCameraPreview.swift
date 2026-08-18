//
//  FaceCameraPreview.swift
//  PillCounter
//
//  Thin AVCaptureVideoPreviewLayer wrapper shared by the enrollment and
//  authentication screens. Mirrors
//  Features/Scanning's CameraView/PreviewView shape.
//

import AVFoundation
import SwiftUI
import UIKit

struct FaceCameraPreview: UIViewRepresentable {
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
        view.cameraPosition = cameraPosition
        view.applyOrientation(for: cameraPosition)
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.cameraPosition = cameraPosition
        uiView.applyOrientation(for: cameraPosition)
    }

    final class PreviewLayerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        /// Cached so layoutSubviews can re-assert the orientation without the
        /// SwiftUI wrapper having to push an update.
        var cameraPosition: AVCaptureDevice.Position = .front

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            // The connection only exists once the session has a running
            // input, and on the first visit the interface is still rotating
            // into the locked orientation when makeUIView runs — so the
            // initial applyOrientation lands too early and the preview shows
            // the previous (portrait) geometry until something forces a
            // re-layout. Re-asserting here fixes that first-visit case.
            applyOrientation(for: cameraPosition)
        }

        /// Matches FaceCameraService.applyConnectionOrientation —
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
