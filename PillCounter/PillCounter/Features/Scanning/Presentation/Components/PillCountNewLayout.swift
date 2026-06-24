//
//  PillCountNewLayout.swift
//  PillCounter
//
//  New full-screen pill-count UI (iPad landscape first) replacing the
//  bottom-sheet `controlsContent`. Composes:
//   • Top bar    — full-width, ignores top safe area, transparent dark bg.
//                  back | NDC/drug name | instruction (center) | glove | Form/Strength/Bucket
//   • Count ring — the ring itself IS the Add / All Done tap target (no separate button)
//   • Bottom bar — full-width transparent bg.
//                  "View all counts" | steps row | horizontal target progress bar
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
    /// Step instruction text — hosted in the top bar (old header content moved here).
    let instructionText: String
    /// Whether the glove-status indicator should show (old header content moved here).
    let showGloveIndicator: Bool

    let onBack: () -> Void
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

    private var isFixed: Bool {
        pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue
    }

    var body: some View {
        ZStack {
            // ── Movable / clickable count ring (the ring itself is the Add target) ──
            MovablePillCountRing(
                count: cameraService.stableCount,
                isTargetReached: isTargetReached,
                isAddDisabled: isAddDisabled,
                isLandscape: isLandscape,
                onAdd: onAdd,
                onAllDone: onAllDone
            )

            // ── Top + bottom bars ──────────────────────────────────────────
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        PillCountTopBar(
            ndc: pillScanViewModel.currentTransaction?.drug?.ndc ?? "-",
            drugName: pillScanViewModel.currentTransaction?.drug?.drug_name ?? "-",
            form: pillScanViewModel.currentTransaction?.drug?.dosage_form ?? "-",
            strength: pillScanViewModel.currentTransaction?.drug?.strength ?? "-",
            bucket: pillScanViewModel.currentTransaction?.bucket_id ?? "-",
            instructionText: instructionText,
            isLandscape: isLandscape,
            isIpad: isIpad,
            cameraService: cameraService,
            showGloveIndicator: showGloveIndicator,
            onBack: onBack
        )
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: isIpad ? 24 : 12) {
            // "View all counts" — opens the full detail grid overlay.
            Button(action: onShowDetailGrid) {
                HStack(spacing: 8) {
                    Text(L10n.PillScan.viewAllCounts)
                        .font(.system(size: isIpad ? 16 : 13, weight: .semibold))
                        .foregroundStyle(appColors.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: isIpad ? 14 : 11, weight: .semibold))
                        .foregroundStyle(appColors.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Steps row (FIXED only) — center.
//            if isFixed {
                ControlledStepRow(
                    activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                    currentStep: pillScanViewModel.currentControlledStep
                )
//            }

            // Horizontal target progress bar — always visible, trailing.
            PillCountTargetProgressBar(
                current: currentTotalCount,
                target: targetCount,
                isIpad: isIpad,
                isLandscape: isLandscape
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, isIpad ? 24 : 14)
        .padding(.vertical, isIpad ? 10 : 8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45))
    }
}

// MARK: - Top bar

struct PillCountTopBar: View {

    @EnvironmentObject private var appColors: AppColors

    let ndc: String
    let drugName: String
    let form: String
    let strength: String
    let bucket: String
    let instructionText: String
    let isLandscape: Bool
    let isIpad: Bool
    let cameraService: CameraService
    let showGloveIndicator: Bool
    let onBack: () -> Void

    var body: some View {
        ZStack {
            // Center: instruction overlay, independent of the side content.
//            if !instructionText.isEmpty {
//                PillCountInstructionOverlay(text: instructionText)
//            }

            HStack(alignment: .center, spacing: isIpad ? 16 : 10) {
                // Back button — leading
                Button(action: onBack) {
                    PillCountingIconView(
                        imageName: "back_icon",
                        size: 24,
                        padding: 0,
                        foregroundColor: appColors.primary,
                        backgroundColor: .clear,
                        scaleOnIpad: true
                    )
                }

                // NDC + drug name
                VStack(alignment: .leading, spacing: 8) {
                    Text("NDC \(ndc)")
                        .font(.system(size: isIpad ? 14 : 11, weight: .regular))
                        .foregroundStyle(appColors.text.opacity(0.85))
                    Text(drugName)
                        .font(.system(size: isIpad ? 18 : 14, weight: .semibold))
                        .foregroundStyle(appColors.text)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showGloveIndicator {
                    GloveStatusIndicator(cameraService: cameraService)
                }

                // Form / Strength / Bucket — bigger.
                HStack(alignment: .top, spacing: isIpad ? 40 : 22) {
                    infoColumn(title: L10n.BarcodeScan.form, value: form)
                    infoColumn(title: L10n.BarcodeScan.strength, value: strength)
                    infoColumn(title: L10n.BarcodeScan.bucket, value: bucket)
                }
            }
            // Equal padding on all sides.
            .padding(isIpad ? 30 : 14)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45))
    }

    @ViewBuilder
    private func infoColumn(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: isIpad ? 16 : 11, weight: .regular))
                .foregroundStyle(appColors.text)
            Text(value)
                .font(.system(size: isIpad ? 24 : 15, weight: .semibold))
                .foregroundStyle(appColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Movable + clickable count ring

/// The count ring is the Add / All Done control itself:
///  • draggable — long-press (hold) to pick it up, then drag to reposition,
///  • tappable  — a tap calls `onAdd` (or `onAllDone` once the target is reached),
///  • target-aware — once `isTargetReached`, the ring tints to the "done" colour and
///    a tap calls `onAllDone` instead.
struct MovablePillCountRing: View {

    @EnvironmentObject private var appColors: AppColors

    let count: Int
    let isTargetReached: Bool
    let isAddDisabled: Bool
    let isLandscape: Bool
    let onAdd: () -> Void
    let onAllDone: () -> Void

    // Drag state — `committedOffset` is the resting position (nil = use default,
    // i.e. never moved), `dragOffset` is the live delta while dragging.
    @State private var committedOffset: CGSize? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var didLoadStoredOffset: Bool = false

    // Ookla-style ripple — animates while the target is reached ("All Done").
    @State private var rippleActive: Bool = false

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var baseSize: CGFloat {
        let s: CGFloat = 120
        guard isIpad else { return s }
        return isLandscape ? s * 2.0 : s * 1.5
    }

    // Default resting position — right side, vertically centered (matches the mockup).
    private func defaultOffset(in size: CGSize) -> CGSize {
        CGSize(width: size.width * 0.30, height: 0)
    }

    /// Clamp the ring's centre offset (from screen centre) so the whole ring stays
    /// on screen. It may slide behind the top/bottom bars, but never off-screen.
    private func clamp(_ offset: CGSize, in size: CGSize) -> CGSize {
        // The ring is centred in the container, so the max offset from centre is
        // half the remaining space after the ring's radius.
        let radius = baseSize / 2
        let maxX = max((size.width  / 2) - radius, 0)
        let maxY = max((size.height / 2) - radius, 0)
        return CGSize(
            width:  min(max(offset.width,  -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    var body: some View {
        GeometryReader { geo in
            let resting = clamp(committedOffset ?? defaultOffset(in: geo.size), in: geo.size)
            ringContent
                .offset(
                    x: resting.width + dragOffset.width,
                    y: resting.height + dragOffset.height
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                // Seed the resting position from the last-saved offset (once).
                .onAppear {
                    guard !didLoadStoredOffset else { return }
                    didLoadStoredOffset = true
                    if let saved = AppStorageManager.shared.pillCountRingOffset {
                        committedOffset = clamp(saved, in: geo.size)
                    }
                }
                // Long-press to "pick up", then drag to move. A plain tap counts as Add.
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture())
                        .onChanged { value in
                            switch value {
                            case .second(true, let drag?):
                                if !isDragging {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        isDragging = true
                                    }
                                }
                                // Clamp live so the ring never crosses the screen edge.
                                let base = clamp(committedOffset ?? defaultOffset(in: geo.size), in: geo.size)
                                let proposed = CGSize(
                                    width: base.width + drag.translation.width,
                                    height: base.height + drag.translation.height
                                )
                                let clamped = clamp(proposed, in: geo.size)
                                dragOffset = CGSize(
                                    width: clamped.width - base.width,
                                    height: clamped.height - base.height
                                )
                            default:
                                break
                            }
                        }
                        .onEnded { value in
                            if case .second(true, let drag?) = value {
                                let base = clamp(committedOffset ?? defaultOffset(in: geo.size), in: geo.size)
                                let dropped = clamp(
                                    CGSize(
                                        width: base.width + drag.translation.width,
                                        height: base.height + drag.translation.height
                                    ),
                                    in: geo.size
                                )
                                committedOffset = dropped
                                // Remember the drop position for next time.
                                AppStorageManager.shared.pillCountRingOffset = dropped
                            }
                            dragOffset = .zero
                            // Animate back to the normal (dropped) size.
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                isDragging = false
                            }
                        }
                )
        }
    }

    private var ringColor: Color {
        if isTargetReached { return appColors.primary }
        return isAddDisabled ? Color.gray : appColors.secondary
    }

    /// Same transparent dark fill used by the top/bottom bars.
    private let ringBackground = Color.black.opacity(0.45)

    private var ringContent: some View {
        ZStack {
            // Ookla-style ripple — expanding, fading rings while "All Done".
            if isTargetReached {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(appColors.primary, lineWidth: isIpad ? 3 : 2)
                        .frame(width: baseSize, height: baseSize)
                        .scaleEffect(rippleActive ? 1.4 : 1.0)
                        .opacity(rippleActive ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 2.8)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 1.4),
                            value: rippleActive
                        )
                }
            }

            // Transparent dark backing for the ring.
            Circle()
                .fill(ringBackground)
                .frame(width: baseSize, height: baseSize)

            Circle()
                .stroke(ringColor, style: StrokeStyle(lineWidth: isIpad ? 5 : 3, lineCap: .round))
                .frame(width: baseSize, height: baseSize)

            // No "Add" label — the count shows alone, then converts to "All Done"
            // (with the ripple above) once the target is reached.
            if isTargetReached {
                Text(L10n.PillCount.allDone)
                    .font(.system(size: baseSize * 0.16, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(count)")
                    .font(.system(size: baseSize * 0.30, weight: .semibold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // The ring itself is the tap target — a tap counts as Add / All Done.
        .contentShape(Circle())
        .onTapGesture { handleTap() }
        // Picked-up state — grows bigger while dragging, with a lifted shadow.
        // The scale change is animated by the gesture's withAnimation blocks.
        .scaleEffect(isDragging ? 1.18 : 1.0)
        .shadow(color: .black.opacity(isDragging ? 0.4 : 0), radius: isDragging ? 16 : 0, y: isDragging ? 8 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isTargetReached)
        .onAppear { rippleActive = isTargetReached }
        .onChange(of: isTargetReached) { _, reached in
            rippleActive = reached
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
}

// MARK: - Horizontal target progress bar

/// Horizontal bar showing how much of the target has been counted.
/// Always visible; shows "current / target" and fills left-to-right.
struct PillCountTargetProgressBar: View {

    @EnvironmentObject private var appColors: AppColors

    let current: Int
    let target: Int
    let isIpad: Bool
    let isLandscape : Bool

    private var fraction: CGFloat {
        guard target > 0 else { return 0 }
        return min(max(CGFloat(current) / CGFloat(target), 0), 1)
    }

    private var trackHeight: CGFloat { isIpad ? 10 : 10 }
    private var trackWidth: CGFloat { isLandscape ? 240 : 160 }

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(appColors.primaryBackground)
                    .frame(width: trackWidth, height: trackHeight)

                Capsule()
                    .fill(appColors.secondary)
                    .frame(width: trackWidth * fraction, height: trackHeight)
                    .animation(.easeInOut(duration: 0.25), value: fraction)
            }
            
            (Text("\(current)/").foregroundStyle(appColors.secondary) + Text("\(target)").foregroundStyle(appColors.text))
                .font(.system(size: isIpad ? 20 : 13, weight: .semibold))
        }
    }
}
