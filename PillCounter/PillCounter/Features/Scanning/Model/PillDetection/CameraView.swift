//
//  CameraView.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import AVFoundation
import SwiftUI

// MARK: - Camera Preview Wrapper


struct CameraView: UIViewRepresentable {

    let session: AVCaptureSession
    @ObservedObject var cameraService: CameraService

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session

        // Expose the preview layer to CameraService
        cameraService.previewLayer = view.previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {

        // 1️⃣ Ensure the preview layer is always bound to the active session
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }

        // 2️⃣ Ensure CameraService always holds the correct preview layer
        if cameraService.previewLayer !== uiView.previewLayer {
            cameraService.previewLayer = uiView.previewLayer
        }

        // 3️⃣ Re-assert preview configuration (can reset on trait changes)
        uiView.previewLayer.videoGravity = .resizeAspectFill

        // 4️⃣ Ensure correct sizing after SwiftUI invalidation
        uiView.setNeedsLayout()
    }
}

// MARK: - Preview View

final class PreviewView: UIView {

    var session: AVCaptureSession? {
        didSet {
            previewLayer.session = session
        }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    /// Defensive rebinding in case SwiftUI detaches the session
    func attachSessionIfNeeded() {
        if previewLayer.session == nil {
            previewLayer.session = session
        }
    }
}

// MARK: - Detection Overlay

struct DetectionOverlay: View {
    

    @ObservedObject var cameraService: CameraService
    @EnvironmentObject var appColors: AppColors

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // Draw only when preview layer & session are valid
                if let layer = cameraService.previewLayer,
                   layer.session != nil
                {
                    ForEach(
                        Array(cameraService.detections.enumerated()),
                        id: \.offset
                    ) { _, det in
                        
                        let screenRect = getScreenRect(
                            for: det,
                            using: layer
                        )
                        
                        let badgeSize: CGFloat = 20
                        
                        Circle()
                            .fill(Color.black.opacity(0.8))
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .frame(width: badgeSize, height: badgeSize)
                            .position(
                                x: screenRect.midX,
                                y: screenRect.midY
                            )
                    }
                }
            }
            
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate Conversion

    private func getScreenRect(
        for det: DetectionResult,
        using layer: AVCaptureVideoPreviewLayer
    ) -> CGRect {

        let normalizedRect = CGRect(
            x: det.rect.origin.x / det.originalFrameSize.width,
            y: det.rect.origin.y / det.originalFrameSize.height,
            width: det.rect.width / det.originalFrameSize.width,
            height: det.rect.height / det.originalFrameSize.height
        )

        return layer.layerRectConverted(
            fromMetadataOutputRect: normalizedRect
        )
    }
}
