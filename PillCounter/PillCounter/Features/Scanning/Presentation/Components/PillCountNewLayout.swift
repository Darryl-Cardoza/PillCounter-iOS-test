//
//  PillCountNewLayout.swift
//  PillCounter
//
//  New full-screen pill-count UI (iPad landscape first) replacing the
//  bottom-sheet `controlsContent`. Composes:
//   • PillCountTopInfoBar      — NDC + drug name (leading), Form / Strength / Bucket (trailing)
//   • MovablePillCountRing     — draggable + tappable count ring; Add → All Done at target
//   • PillCountTargetProgressBar — vertical "current of target" progress on the right edge
//   • ControlledStepRow        — existing steps component (reused)
//   • "View all counts" button — opens the full detail grid overlay
//
//  No counting/transaction LOGIC lives here — all actions are forwarded to the
//  closures the host (UnifiedCameraView) passes in. Data is read straight off
//  the same view-model fields the old BottomControlsView used so the numbers match.
//

import SwiftUI

// MARK: - Root layout

struct PillCountNewLayout: View {

    @EnvironmentObject private var appColors: AppColors

    let pillScanViewModel: PillScanViewModel
    let cameraService: CameraService
    let countType: CountType
    let isLandscape: Bool
    let isAddDisabled: Bool

    let onAdd: () -> Void
    let onAllDone: () -> Void
    let onShowDetailGrid: () -> Void

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // ── Data mirrors BottomControlsView so the displayed numbers are identical ──

    /// Target for the current step (0 when there is no meaningful target, e.g. REGULAR).
    private var targetCount: Int {
        if pillScanViewModel.currentTransaction?.is_from_pms == true {
            return pillScanViewModel.currentControlledTargetCount ?? 0
        } else if pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue {
            return 0
        } else {
            return pillScanViewModel.currentControlledTargetCount ?? 0
        }
    }

    /// Total committed count for the current transaction / step.
    private var currentTotalCount: Int {
        if pillScanViewModel.currentTransaction?.is_from_pms == true {
            return Int(pillScanViewModel.getTotalCuntForCurrentStep())
        } else if pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue {
            return pillScanViewModel.addCurrentOpenPillCount
        } else {
            return pillScanViewModel.getTotalPillCountOfCurrentTransaction()
        }
    }

    /// True once the committed total reaches the step target — ring shows "All Done".
    private var isTargetReached: Bool {
        targetCount > 0 && currentTotalCount >= targetCount
    }

    private var showProgressBar: Bool {
        countType == .FIXED && targetCount > 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── Top info bar ──────────────────────────────────────────────
            VStack {
                PillCountTopInfoBar(
                    ndc: pillScanViewModel.currentTransaction?.drug?.ndc ?? "-",
                    drugName: pillScanViewModel.currentTransaction?.drug?.drug_name ?? "-",
                    form: pillScanViewModel.currentTransaction?.drug?.dosage_form ?? "-",
                    strength: pillScanViewModel.currentTransaction?.drug?.strength ?? "-",
                    bucket: pillScanViewModel.currentTransaction?.bucket_id ?? "-",
                    isIpad: isIpad
                )
                Spacer()
            }

            // ── Right-edge vertical target progress bar ───────────────────
            if showProgressBar {
                HStack {
                    Spacer()
                    PillCountTargetProgressBar(
                        current: currentTotalCount,
                        target: targetCount,
                        isIpad: isIpad
                    )
                    .padding(.trailing, isIpad ? 24 : 14)
                }
            }

            // ── Movable / clickable count ring ────────────────────────────
            MovablePillCountRing(
                count: cameraService.stableCount,
                currentTotalCount: currentTotalCount,
                targetCount: targetCount,
                isTargetReached: isTargetReached,
                isAddDisabled: isAddDisabled,
                isLandscape: isLandscape,
                onAdd: onAdd,
                onAllDone: onAllDone
            )

            // ── Steps row + "View all counts" ─────────────────────────────
            VStack {
                Spacer()
                bottomRow
            }
        }
    }

    private var bottomRow: some View {
        HStack(alignment: .center) {
            // "View all counts" — opens the full detail grid overlay.
            Button(action: onShowDetailGrid) {
                HStack(spacing: 4) {
                    Text(L10n.PillScan.viewAllCounts)
                        .font(.system(size: isIpad ? 16 : 13, weight: .semibold))
                        .foregroundStyle(appColors.text)
                    Image(systemName: "chevron.right")
                        .font(.system(size: isIpad ? 14 : 11, weight: .semibold))
                        .foregroundStyle(appColors.text)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(appColors.primaryBackground.opacity(0.5))
                .clipShape(Capsule())
            }

            Spacer()

            // Reuse the existing controlled-step row for FIXED transactions.
            if pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
                ControlledStepRow(
                    activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                    currentStep: pillScanViewModel.currentControlledStep
                )
            }

            Spacer()
            // Balance the leading "View all counts" so the steps row stays centered.
            Color.clear.frame(width: isIpad ? 160 : 110, height: 1)
        }
        .padding(.horizontal, isIpad ? 24 : 14)
        .padding(.bottom, isIpad ? 24 : 14)
    }
}

// MARK: - Top info bar

struct PillCountTopInfoBar: View {

    @EnvironmentObject private var appColors: AppColors

    let ndc: String
    let drugName: String
    let form: String
    let strength: String
    let bucket: String
    let isIpad: Bool

    var body: some View {
        HStack(alignment: .top) {
            // Leading: NDC + drug name
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L10n.BarcodeScan.ndcNumber) \(ndc)")
                    .font(.system(size: isIpad ? 14 : 12, weight: .regular))
                    .foregroundStyle(appColors.text.opacity(0.85))
                Text(drugName)
                    .font(.system(size: isIpad ? 18 : 15, weight: .semibold))
                    .foregroundStyle(appColors.text)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            // Trailing: Form / Strength / Bucket
            HStack(alignment: .top, spacing: isIpad ? 28 : 18) {
                infoColumn(title: L10n.BarcodeScan.form, value: form)
                infoColumn(title: L10n.BarcodeScan.strength, value: strength)
                infoColumn(title: L10n.BarcodeScan.bucket, value: bucket)
            }
        }
        .padding(.horizontal, isIpad ? 20 : 14)
        .padding(.vertical, isIpad ? 12 : 10)
        .background(appColors.primaryBackground.opacity(0.45))
        .padding(.horizontal, isIpad ? 12 : 8)
        .padding(.top, isIpad ? 12 : 8)
    }

    @ViewBuilder
    private func infoColumn(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.system(size: isIpad ? 12 : 10, weight: .regular))
                .foregroundStyle(appColors.text.opacity(0.7))
            Text(value)
                .font(.system(size: isIpad ? 16 : 13, weight: .semibold))
                .foregroundStyle(appColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Movable + clickable count ring

/// Wraps the existing PillCountRingView visual and makes it:
///  • draggable — long-press (hold) to pick it up, then drag to reposition,
///  • tappable  — a tap calls `onAdd`,
///  • target-aware — once `isTargetReached`, the Add affordance becomes "All Done"
///    and a tap calls `onAllDone` instead.
struct MovablePillCountRing: View {

    @EnvironmentObject private var appColors: AppColors

    let count: Int
    let currentTotalCount: Int
    let targetCount: Int
    let isTargetReached: Bool
    let isAddDisabled: Bool
    let isLandscape: Bool
    let onAdd: () -> Void
    let onAllDone: () -> Void

    // Drag state — `offset` is the committed position, `dragOffset` the live delta.
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var baseSize: CGFloat {
        let s: CGFloat = 120
        guard isIpad else { return s }
        return isLandscape ? s * 2.0 : s * 1.5
    }

    // Default resting position — right side, vertically centered (matches the mockup).
    private func defaultOffset(in size: CGSize) -> CGSize {
        CGSize(width: size.width * 0.32, height: 0)
    }

    var body: some View {
        GeometryReader { geo in
            ringContent
                .offset(
                    x: (offset == .zero ? defaultOffset(in: geo.size).width : offset.width) + dragOffset.width,
                    y: (offset == .zero ? defaultOffset(in: geo.size).height : offset.height) + dragOffset.height
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                // Long-press to "pick up", then drag to move. A plain tap still
                // falls through to the button action below.
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture())
                        .onChanged { value in
                            switch value {
                            case .second(true, let drag?):
                                isDragging = true
                                dragOffset = drag.translation
                            default:
                                break
                            }
                        }
                        .onEnded { value in
                            if case .second(true, let drag?) = value {
                                let base = offset == .zero ? defaultOffset(in: geo.size) : offset
                                offset = CGSize(
                                    width: base.width + drag.translation.width,
                                    height: base.height + drag.translation.height
                                )
                            }
                            dragOffset = .zero
                            isDragging = false
                        }
                )
        }
    }

    private var ringContent: some View {
        VStack(spacing: isIpad ? -8 : -16) {
            ZStack {
                Circle()
                    .stroke(appColors.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: baseSize, height: baseSize)

                Text("\(count)")
                    .font(.system(size: baseSize * 0.28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // Tapping the ring itself counts as Add / All Done.
            .contentShape(Circle())
            .onTapGesture { handleTap() }

            actionButton
        }
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isTargetReached {
            Button(action: onAllDone) {
                Text(L10n.PillCount.allDone)
                    .font(.system(size: isIpad ? 18 : 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, isIpad ? 36 : 28)
                    .padding(.vertical, isIpad ? 12 : 10)
                    .background(appColors.secondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(NoPressEffectStyle())
        } else {
            Button(action: handleTap) {
                Text(isAddDisabled ? L10n.PillCount.addButtonWait : L10n.PillCount.addButton)
                    .font(.system(size: isIpad ? 18 : 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, isIpad ? 36 : 28)
                    .padding(.vertical, isIpad ? 12 : 10)
                    .background(isAddDisabled ? Color.gray : appColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(NoPressEffectStyle())
            .disabled(isAddDisabled)
        }
    }

    private func handleTap() {
        guard !isDragging else { return }
        if isTargetReached {
            onAllDone()
        } else {
            guard !isAddDisabled else { return }
            onAdd()
        }
    }

    struct NoPressEffectStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label }
    }
}

// MARK: - Vertical target progress bar

/// Right-side vertical bar showing how much of the target has been counted.
/// Fills bottom-up and shows "current / target" at the top.
struct PillCountTargetProgressBar: View {

    @EnvironmentObject private var appColors: AppColors

    let current: Int
    let target: Int
    let isIpad: Bool

    private var fraction: CGFloat {
        guard target > 0 else { return 0 }
        return min(max(CGFloat(current) / CGFloat(target), 0), 1)
    }

    private var trackWidth: CGFloat { isIpad ? 14 : 10 }
    private var trackHeight: CGFloat { isIpad ? 320 : 200 }

    var body: some View {
        VStack(spacing: 10) {
            Text("\(current)/\(target)")
                .font(.system(size: isIpad ? 16 : 13, weight: .bold))
                .foregroundStyle(appColors.text)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(appColors.primaryBackground.opacity(0.5))
                    .frame(width: trackWidth, height: trackHeight)

                Capsule()
                    .fill(appColors.secondary)
                    .frame(width: trackWidth, height: trackHeight * fraction)
                    .animation(.easeInOut(duration: 0.25), value: fraction)
            }
        }
    }
}
