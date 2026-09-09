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
    @State private var scanTimeoutTask: Task<Void, Never>?

    /// How long a scan attempt runs before we give up and show the failure
    /// screen — the underlying pipeline has no terminal "no match" state by
    /// design (see FaceAuthenticationViewModel), it just keeps retrying
    /// frames, so this timeout is what turns that into a bounded attempt.
    private let scanTimeout: TimeInterval = 7
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
        .onAppear(perform: autoStartScanIfNeeded)
        .onChange(of: sessionManager.shouldAutoStartScan) { _, _ in
            autoStartScanIfNeeded()
        }
    }

    /// Post-login lock sets `shouldAutoStartScan` and expects the camera to
    /// open immediately rather than waiting for the "Unlock" tap — see
    /// `FaceSessionManager.lockAfterLogin()`.
    private func autoStartScanIfNeeded() {
        guard sessionManager.shouldAutoStartScan, sessionManager.lockState == .locked else { return }
        sessionManager.consumeAutoStartScan()
        startScan()
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
            scanTimeoutTask?.cancel()
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
            scanTimeoutTask?.cancel()
            sessionManager.unlock(userId: userId, userName: userName)
        }
        viewModel.startAuthentication()

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(scanTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            stopScan()
            sessionManager.markFailed()
        }
    }

    private func stopScan() {
        OrientationLock.shared.unlock()
        viewModel.stopAuthentication()
    }

    private func handleLockStateChange(_ newState: SessionLockState) {
        switch newState {
        case .locked, .failed:
            scanTimeoutTask?.cancel()
            stopScan()

        case .unlocked:
            scanTimeoutTask?.cancel()
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
