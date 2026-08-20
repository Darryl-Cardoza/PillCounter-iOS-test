//
//  FaceScanScreen.swift
//  PillCounter
//
//  Full-bleed scanning UI (spec mock): the live preview fills the screen,
//  a back control and title sit on top of it, a rounded rectangle marks
//  where the face goes, and the pipeline's instruction text floats in a
//  dark pill at the bottom.
//
//  Presentation only — it renders whatever AuthenticationState and
//  instruction text it is handed. All detection/quality/matching logic
//  stays in FaceAuthenticationViewModel, unchanged.
//

import SwiftUI
import UIKit

struct FaceScanScreen<Guidance: View>: View {

    @ObservedObject var cameraService: FaceCameraService
    @EnvironmentObject private var appColors: AppColors

    let state: AuthenticationState
    let instructionText: String
    var title: String = L10n.FaceAuth.scanFaceTitle
    var showsFlipCamera: Bool = false
    /// Overrides the state-derived spinner. Enrollment drives its own
    /// pipeline (EnrollmentState), which doesn't map onto AuthenticationState.
    var isBusy: Bool?
    /// Guide colour override — enrollment turns the frame green once a pose
    /// is held, which authentication has no equivalent for.
    var guideColorOverride: Color?
    let onBack: () -> Void
    /// Extra controls stacked above the instruction pill — enrollment puts
    /// its pose-direction arrows and progress bar here. Empty for auth.
    @ViewBuilder var guidance: () -> Guidance

    var body: some View {
        ZStack {
            appColors.primaryBackground.ignoresSafeArea()

            // Full-bleed on every device, iPad included — the guide square
            // (a fraction of the narrower edge) is what says "stand here",
            // so the preview itself doesn't need narrowing. Alignment and
            // matching are unaffected either way: FaceAligner works on the
            // raw camera buffer, never on what's displayed.
            FaceCameraPreview(
                session: cameraService.previewSession,
                deviceOrientation: cameraService.currentCameraOrientation,
                isMirrored: cameraService.cameraPosition == .front
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(FaceFrameGuide(color: guideColor))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                guidance()
                instructionPill
            }
        }
        .statusBarHidden(false)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                Button(action: onBack) {
                    // Same control BaseView renders, so the scan screen's
                    // back affordance matches every other screen.
                    PillCountingIconView(
                        imageName: "back_icon",
                        size: 24,
                        padding: 12,
                        foregroundColor: appColors.primary,
                        backgroundColor: .clear,
                        scaleOnIpad: true
                    )
                }

                Spacer()

                if showsFlipCamera {
                    Button {
                        cameraService.flipCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Instruction

    private var instructionPill: some View {
        HStack(spacing: 10) {
            if isProcessingFrame {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.8)
            }

            Text(instructionText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.75))
        )
        .frame(maxWidth: 320)
        .padding(.bottom, 24)
        .animation(.easeInOut(duration: 0.2), value: instructionText)
    }

    // MARK: - State-driven styling (same rules as FaceScanSurface)

    private var isProcessingFrame: Bool {
        if let isBusy { return isBusy }
        switch state {
        case .faceDetected, .qualityChecking, .generatingEmbedding,
             .comparing, .candidateFound, .confirmingIdentity:
            return true
        default:
            return false
        }
    }

    /// Theme colours only — the guide stays on-brand rather than switching to
    /// stock green/red/orange, so state is conveyed by the instruction text.
    private var guideColor: Color {
        if let guideColorOverride { return guideColorOverride }
        switch state {
        case .authenticated, .candidateFound, .confirmingIdentity:
            return appColors.secondary
        default:
            return appColors.primary
        }
    }
}

extension FaceScanScreen where Guidance == EmptyView {
    init(
        cameraService: FaceCameraService,
        state: AuthenticationState,
        instructionText: String,
        title: String = L10n.FaceAuth.scanFaceTitle,
        showsFlipCamera: Bool = false,
        onBack: @escaping () -> Void
    ) {
        self.init(
            cameraService: cameraService,
            state: state,
            instructionText: instructionText,
            title: title,
            showsFlipCamera: showsFlipCamera,
            onBack: onBack
        ) { EmptyView() }
    }
}

/// "Put your face here" frame — no dimmed surround, so the user can see
/// themselves at full brightness while aligning.
private struct FaceFrameGuide: View {

    let color: Color

    var body: some View {
        GeometryReader { geometry in
            // Head-sized square: a fraction of the narrower edge, sat a
            // little above centre so the chin isn't pushed out of frame
            // when the user aligns their eyes with the middle.
            let side = min(geometry.size.width, geometry.size.height) * 0.62

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color, lineWidth: 2)
                .frame(width: side, height: side)
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2 - geometry.size.height * 0.04
                )
                .animation(.easeInOut(duration: 0.25), value: color)
        }
        .allowsHitTesting(false)
    }
}
