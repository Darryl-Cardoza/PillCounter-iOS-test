//
//  IdScanCameraPreview.swift
//  PillCounter
//
//  AVCaptureVideoPreviewLayer wrapper for the ID scan step. Same shape as
//  FaceCameraPreview, including re-asserting the rotation angle on its own
//  connection in updateUIView when deviceOrientation changes.
//

import AVFoundation
import SwiftUI
import UIKit

struct IdScanCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
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

        var deviceOrientation: UIDeviceOrientation = .portrait

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            applyOrientation()
        }

        func applyOrientation() {
            guard let connection = previewLayer.connection else { return }
            let angle = IdScanCameraService.rotationAngle(for: deviceOrientation)
            guard connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}
