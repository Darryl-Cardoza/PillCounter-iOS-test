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
    /// Device orientation the preview layer's OWN connection (separate from
    /// AVCaptureVideoDataOutput's) should be rotated to. Passing it in — rather
    /// than reading the device here — is what makes SwiftUI re-run
    /// `updateUIView` on rotation, so the preview follows the device instead of
    /// staying pinned to whatever it was when the screen appeared.
    var deviceOrientation: UIDeviceOrientation = .portrait

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.deviceOrientation = deviceOrientation
        view.applyOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.deviceOrientation = deviceOrientation
        uiView.applyOrientation()
    }

    final class PreviewLayerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        /// Cached so layoutSubviews can re-assert the orientation without the
        /// SwiftUI wrapper having to push an update.
        var deviceOrientation: UIDeviceOrientation = .portrait

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            // The connection only exists once the session has a running
            // input, and on the first visit the interface is still rotating
            // into the locked orientation when makeUIView runs — so the
            // initial applyOrientation lands too early and the preview shows
            // the previous geometry until something forces a re-layout.
            // Re-asserting here fixes that first-visit case, and covers
            // rotation too since layout runs again on every bounds change.
            applyOrientation()
        }

        /// Rotates by device orientation only, using the same angle table as
        /// FaceCameraService. Camera position is deliberately NOT a factor —
        /// front/back differ by mirroring, which the session's own connection
        /// handles; folding it into the rotation angle here is what previously
        /// left the flipped camera 180° off.
        func applyOrientation() {
            guard let connection = previewLayer.connection else { return }
            let angle = FaceCameraService.rotationAngle(for: deviceOrientation)
            guard connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}
