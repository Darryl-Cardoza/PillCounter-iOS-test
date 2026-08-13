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
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(appColors.primary)

            Text(L10n.FaceAuth.sessionLockedTitle)
                .font(.title2.bold())
                .foregroundStyle(appColors.text)

            Text(sessionManager.idleDurationText ?? L10n.FaceAuth.sessionLockedSubtitle)
                .font(.subheadline)
                .foregroundStyle(appColors.text.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            PillCountingButton(
                iconName: nil,
                title: L10n.FaceAuth.sessionLockedUnlockButton,
                textColor: .white,
                backgroundColor: appColors.primary,
                borderColor: .clear,
                font: .system(size: 15, weight: .semibold),
                cornerRadius: 30,
                horizontalPadding: 36,
                verticalPadding: 16,
                iconSize: 0,
                action: startScan
            )
            .fixedSize()
            .padding(.top, 12)
        }
        .padding()
    }

    // MARK: - SCANNING (transitional)

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(appColors.primary)
                .scaleEffect(1.4)

            Text(viewModel.instructionText)
                .font(.headline)
                .foregroundStyle(appColors.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    // MARK: - UNLOCKED (welcome-back transitional)

    private func unlockedView(userName: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.green)

            Text(String(format: L10n.FaceAuth.sessionWelcomeBack, userName))
                .font(.title2.bold())
                .foregroundStyle(appColors.text)

            Text(L10n.FaceAuth.sessionRestoring)
                .font(.subheadline)
                .foregroundStyle(appColors.text.opacity(0.7))
        }
        .padding()
    }

    // MARK: - FAILED

    private var failedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.red)

            Text(L10n.FaceAuth.sessionFailedTitle)
                .font(.title2.bold())
                .foregroundStyle(appColors.text)

            Text(L10n.FaceAuth.sessionFailedSubtitle)
                .font(.subheadline)
                .foregroundStyle(appColors.text.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                PillCountingButton(
                    iconName: nil,
                    title: L10n.FaceAuth.cancel,
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 15, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 28,
                    verticalPadding: 16,
                    iconSize: 0,
                    action: { sessionManager.cancelScan() }
                )
                PillCountingButton(
                    iconName: nil,
                    title: L10n.FaceAuth.retry,
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 15, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 28,
                    verticalPadding: 16,
                    iconSize: 0,
                    action: startScan
                )
            }
            .padding(.top, 12)
        }
        .padding()
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
