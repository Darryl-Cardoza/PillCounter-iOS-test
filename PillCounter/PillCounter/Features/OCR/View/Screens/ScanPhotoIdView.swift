//
//  ScanPhotoIdView.swift
//  PillCounter
//
//  Camera preview + ID-shaped guide + status pill + result sheet. Name in,
//  name out — the host (FaceEnrollmentView) owns firstName/lastName; this
//  view holds no scan state of its own, everything it renders reads off
//  IdScanViewModel. See
//  plans/face-auth/ocr/19-08-2026-12-31-ocr-id-scan.md §4.2.
//

import Combine
import SwiftUI

struct ScanPhotoIdView: View {

    @StateObject private var viewModel = IdScanViewModel()
    @Binding var firstName: String
    @Binding var lastName: String
    let onBack: () -> Void
    /// Returns nil to allow Continue to proceed, or a localized error to show
    /// inline in the sheet (e.g. the duplicate-name check).
    let validateName: () -> String?
    let onContinue: () -> Void

    @EnvironmentObject private var appColors: AppColors

    /// Portrait sheet height as a fraction of safe-area height: collapsed at
    /// rest, expanded while the keyboard is up so the name fields stay
    /// visible above it instead of being covered.
    @State private var sheetHeight: CGFloat = 0
    private static let collapsedFraction: CGFloat = 0.60
    private static let expandedFraction: CGFloat = 0.75

    var body: some View {
        GeometryReader { geometry in
            let safeAreaHeight = geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom
            content(safeAreaHeight: safeAreaHeight)
        }
        .ignoresSafeArea()
    }

    private func content(safeAreaHeight: CGFloat) -> some View {
        ZStack {
            appColors.primaryBackground.ignoresSafeArea()

            if viewModel.cameraService.isAuthorized {
                // Full-bleed, no crop — the guide is visual only. The full
                // frame goes to the recognizer; cropping would change
                // behaviour for loosely framed cards and shift the
                // prominence tier's height comparisons.
                IdScanCameraPreview(
                    session: viewModel.cameraService.previewSession,
                    deviceOrientation: viewModel.cameraService.currentCameraOrientation
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(IdCardGuide())
                .ignoresSafeArea()
            } else {
                NoCameraPermissionView()
            }

            VStack(spacing: 0) {
                header
                Spacer()
                bottomCard
            }
        }
        .bottomSheet(isPresented: $viewModel.isSheetPresented, heightBinding: $sheetHeight, onDismiss: {
            viewModel.sheetDismissed()
        }) {
            IdNameSheetContent(
                firstName: $firstName,
                lastName: $lastName,
                viewModel: viewModel,
                onContinue: {
                    if let error = validateName() {
                        viewModel.nameError = error
                    } else {
                        viewModel.nameError = nil
                        onContinue()
                    }
                }
            )
        }
        .onAppear {
            viewModel.bind(
                setFirstName: { firstName = $0 },
                setLastName: { lastName = $0 }
            )
            viewModel.start()
            sheetHeight = safeAreaHeight * Self.collapsedFraction
        }
        .onDisappear {
            viewModel.stop()
        }
        .onReceive(Publishers.keyboardHeight) { height in
            withAnimation(.easeInOut(duration: 0.28)) {
                sheetHeight = safeAreaHeight * (height > 0 ? Self.expandedFraction : Self.collapsedFraction)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(L10n.FaceAuth.IdScan.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                Button(action: onBack) {
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
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, SafeAreaInsets.top)
    }

    // MARK: - Bottom card

    private var bottomCard: some View {
        VStack(spacing: 12) {
            statusPill

            Text(L10n.FaceAuth.IdScan.hint)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Button(action: viewModel.enterManually) {
                Text(L10n.FaceAuth.IdScan.enterManually)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .underline()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.75))
        )
        .padding(.bottom, 24)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .scanning: return appColors.secondary
        case .paused: return appColors.text
        case .restarting: return .red
        }
    }

    private var statusText: String {
        switch viewModel.status {
        case .scanning: return L10n.FaceAuth.IdScan.statusScanning
        case .paused: return L10n.FaceAuth.IdScan.statusPaused
        case .restarting: return L10n.FaceAuth.IdScan.statusRestarting
        }
    }
}

/// ID-shaped guide at ISO/IEC 7810 ID-1 aspect ratio (1.586:1), sized off the
/// narrower edge so iPad framing stays sane. Visual only — see the "no crop"
/// note above.
private struct IdCardGuide: View {
    private static let aspectRatio: CGFloat = 1.586

    var body: some View {
        GeometryReader { geometry in
            let narrowerEdge = min(geometry.size.width, geometry.size.height)
            let width = narrowerEdge * 0.85
            let height = width / Self.aspectRatio

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: width, height: height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}
