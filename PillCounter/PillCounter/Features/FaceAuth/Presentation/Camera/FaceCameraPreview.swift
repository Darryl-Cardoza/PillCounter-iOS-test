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
    /// Whether the active camera is the front (mirrored) one — the rotation
    /// angle for landscape differs between mirrored and unmirrored cameras,
    /// same reasoning as FaceCameraService.applyConnectionOrientation.
    var isMirrored: Bool = true

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.deviceOrientation = deviceOrientation
        view.isMirrored = isMirrored
        view.applyOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.deviceOrientation = deviceOrientation
        uiView.isMirrored = isMirrored
        uiView.applyOrientation()
    }

    final class PreviewLayerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        /// Cached so layoutSubviews can re-assert the orientation without the
        /// SwiftUI wrapper having to push an update.
        var deviceOrientation: UIDeviceOrientation = .portrait
        var isMirrored: Bool = true

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

        /// Rotates by device orientation, using the same angle table as
        /// FaceCameraService — including the mirrored flag, since a mirrored
        /// (front) camera needs the opposite landscape angle from an
        /// unmirrored (back) one for the same physical device orientation.
        func applyOrientation() {
            guard let connection = previewLayer.connection else { return }
            let angle = FaceCameraService.rotationAngle(for: deviceOrientation, mirrored: isMirrored)
            guard connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}
