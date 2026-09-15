//
//  SessionLockOverlay.swift
//  PillCounter
//
//  Global lock screen (spec sections 3/4/D). Presented as a root-level
//  overlay above AppNavigation — see PillCounterApp — so it blocks all
//  interaction underneath regardless of what screen is on the nav stack.
//  Reuses FaceAuthenticationViewModel exactly as-is for the scan itself
//  (detection quality gates, embedding, 1:N identify, threshold/margin
//  checks all live there — this file only reacts to its published state).
//

import SwiftUI

struct SessionLockOverlay: View {

    @ObservedObject private var sessionManager = FaceSessionManager.shared
    @EnvironmentObject private var appColors: AppColors

    @StateObject private var viewModel = FaceAuthenticationViewModel()

    private let welcomeDismissDelay: TimeInterval = 1.5

    var body: some View {
        ZStack {
            Color.black.opacity(0.001) // catches taps so nothing below reacts
                .ignoresSafeArea()

            appColors.primaryBackground
                .ignoresSafeArea()

            content
        }
        .onChange(of: sessionManager.lockState) { _, newState in
            handleLockStateChange(newState)
        }
        .onChange(of: viewModel.state) { _, newState in
            // The VM's own scanBudgetSeconds is the sole scan timeout — it
            // already stops the camera and publishes .failed when the budget
            // expires (see FaceAuthenticationViewModel.failScanAsUnrecognized).
            // This just forwards that outcome into the session's lock state.
            guard case .failed = newState else { return }
            sessionManager.markFailed()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sessionManager.lockState {
        case .locked:
            lockedView
        case .scanning:
            scanningView
        case .unlocked(let userName):
            unlockedView(userName: userName)
        case .failed:
            failedView
        }
    }

    // MARK: - LOCKED

    private var lockedView: some View {
        SessionStatusScreen(
            iconName: "icon_session_lock",
            title: L10n.FaceAuth.sessionLockedTitle,
            subtitle: L10n.FaceAuth.sessionLockedSubtitle
        ) {
            PillCountingButton(
                title: L10n.FaceAuth.sessionLockedUnlockButton,
                textColor: .white,
                backgroundColor: appColors.primary,
                action: startScan,
                width: 160
            )
            .frame(width: 160)
        }
    }

    // MARK: - SCANNING

    /// Shows the same viewfinder as FaceAuthenticationView (via the shared
    /// FaceScanSurface) rather than a bare spinner — without a preview the
    /// user has no idea where to look while the scan runs.
    private var scanningView: some View {
        FaceScanScreen(
            cameraService: viewModel.cameraService,
            state: viewModel.state,
            instructionText: viewModel.instructionText
        ) {
            stopScan()
            sessionManager.cancelScan()
        }
    }

    // MARK: - UNLOCKED (welcome-back transitional)

    private func unlockedView(userName: String) -> some View {
        SessionStatusScreen(
            iconName: "done_icon",
            title: String(format: L10n.FaceAuth.sessionWelcomeBack, userName),
            subtitle: L10n.FaceAuth.sessionRestoring
        )
    }

    // MARK: - FAILED

    private var failedView: some View {
        SessionStatusScreen(
            iconName: "icon_close",
            title: L10n.FaceAuth.sessionFailedTitle,
            subtitle: L10n.FaceAuth.sessionFailedSubtitle
        ) {
            SessionActionButtonPair(
                onCancel: { sessionManager.cancelScan() },
                onConfirm: startScan
            )
        }
    }

    // MARK: - Scan lifecycle

    private func startScan() {
        sessionManager.beginScanning()

        OrientationLock.shared.lockForFaceCapture()
        viewModel.onAuthenticated = { userId, userName in
            sessionManager.unlock(userId: userId, userName: userName)
        }
        viewModel.startAuthentication()
    }

    private func stopScan() {
        OrientationLock.shared.unlock()
        viewModel.stopAuthentication()
    }

    private func handleLockStateChange(_ newState: SessionLockState) {
        switch newState {
        case .locked, .failed:
            stopScan()

        case .unlocked:
            stopScan()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(welcomeDismissDelay * 1_000_000_000))
                sessionManager.dismissOverlay()
            }

        case .scanning:
            break
        }
    }
}

#Preview {
    SessionLockOverlay()
        .environmentObject(AppColors.shared)
}
