//
//  OfflineOverlayView.swift
//  PillCounter
//

import SwiftUI

/// Global offline indicator: a red rounded-border decoration drawn on top of
/// every screen (app stays fully interactive underneath) plus a bottom-left
/// animated hourglass button that reveals a live logout countdown on tap.
struct OfflineOverlayView: View {
    @ObservedObject private var offlineManager = OfflineSessionManager.shared
    @Environment(\.isLandscape) private var isLandscape
    @State private var isBadgeVisible = false
    @State private var hideBadgeTask: Task<Void, Never>?

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var borderWidth: CGFloat { isIpad ? 6 : 4 }
    /// No public API exposes the device's real display corner radius —
    /// these are tuned to visually match a notch/Dynamic Island iPhone and
    /// an iPad, without relying on private APIs.
    private var borderCornerRadius: CGFloat { isIpad ? 24 : 60 }

    var body: some View {
        if offlineManager.isOffline {
            ZStack(alignment: .bottomLeading) {
                borderDecoration
                hourglassAndBadge
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: offlineManager.isOffline)
        }
    }

    private var borderDecoration: some View {
        RoundedRectangle(cornerRadius: borderCornerRadius, style: .continuous)
            .stroke(Color.red, lineWidth: borderWidth)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var hourglassAndBadge: some View {
        HStack(spacing: 8) {
            Button(action: toggleBadge) {
                SandTimerIcon(size: hourglassIconSize, color: .white)
                    .padding(10)
                    .background(Circle().fill(Color.red))
            }

            if isBadgeVisible {
                // OfflineSessionManager.tick is a @Published bumped every second
                // while offline — any change to it re-renders this @ObservedObject
                // view, refreshing `remainingOfflineTime` below live.
                Text(DurationFormatter.logoutWarningText(offlineManager.remainingOfflineTime))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.red.opacity(0.9)))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.leading, 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isBadgeVisible)
    }

    private var hourglassIconSize: CGFloat { isIpad ? 24 : 20 }

    private func toggleBadge() {
        hideBadgeTask?.cancel()
        isBadgeVisible = true
        hideBadgeTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isBadgeVisible = false }
        }
    }
}
