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
        
        uiView.attachSessionIfNeeded()
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

    /// Dispense target quantity for the current step. The excess-near-chute
    /// highlight is ENABLED only when this is > 0 (a real dispense target). When
    /// it is 0 the feature is OFF entirely — every pill dot is drawn black exactly
    /// like regular (non-target) counting; nothing is treated as "exceed". When
    /// the live tray holds MORE pills than the target, the surplus pills closest
    /// to the chute are drawn BLACK while all other (within-target) pills are drawn
    /// in `appColors.secondary`, so the operator can see which to remove.
    var targetQuantity: Int = 0

    /// Stateful near-chute picker. Held across frames so its temporal hysteresis
    /// (remembering last frame's highlighted pills) can stop adjacent, nearly
    /// equidistant pills from ping-ponging the highlight every frame. A reference
    /// type kept in @State — we never want SwiftUI to observe it, only to persist
    /// the same instance across re-renders.
    @State private var chuteProximity = ChuteProximity()

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // Draw only when preview layer & session are valid
                if let layer = cameraService.previewLayer,
                   layer.session != nil
                {
                    // ── Excess-near-chute highlight set ───────────────────────
                    // Only when a real target is set (targetQuantity > 0). Number
                    // of pills to highlight uses the SMOOTHED stableCount (steady),
                    // while WHICH pills are picked is re-ranked from the live
                    // detections each frame (responsive). The chute geometry comes
                    // from the same frame's segmentation result. With target 0 the
                    // feature is off and highlightedIDs is empty → all dots black.
                    let excess = targetQuantity > 0
                        ? max(0, cameraService.stableCount - targetQuantity)
                        : 0
                    let chute = cameraService.trayDetections.first { $0.trayClass == .chute }
                    let tray = cameraService.trayDetections.first { $0.trayClass == .tray }
                    let highlightedIDs = chuteProximity.nearChuteIDs(
                        pills: cameraService.detections,
                        chute: chute,
                        tray: tray,
                        excess: excess
                    )

                    ForEach(
                        Array(cameraService.detections.enumerated()),
                        id: \.offset
                    ) { _, det in

                        let screenRect = getScreenRect(
                            for: det,
                            using: layer
                        )

                        let badgeSize: CGFloat = 16
                        let isNearChute = highlightedIDs.contains(det.id)

                        Circle()
                            .fill(isNearChute ? Color.black.opacity(0.8) : appColors.secondary)
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
