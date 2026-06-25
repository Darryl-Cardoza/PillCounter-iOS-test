//
//  PillCountLayout.swift
//  PillCounter
//
//  Full-screen pill-count UI (iPad landscape first) replacing the
//  bottom-sheet `controlsContent`. Composes:
//   • Top bar    — `PillCountTopBar`
//   • Count ring — `MovablePillCountRing` (the ring itself IS the Add / All Done tap target)
//   • Bottom bar — `PillCountBottomBar` (view-all, steps row, target progress bar)
//
//  No counting/transaction LOGIC lives here — all actions are forwarded to the
//  closures the host (UnifiedCameraView) passes in. Data is read straight off
//  the same view-model fields the old BottomControlsView used so the numbers match.
//

import SwiftUI

struct PillCountLayout: View {

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

    // ── Step instruction tooltip ───────────────────────────────────────────
    // Rendered at this (full-screen) level so it can float above the current
    // step icon without being clipped by the bottom bar. Auto-shown for
    // `tooltipDuration` on appear and on every step change; re-shown when the
    // user taps the current step.
    @EnvironmentObject private var appColors: AppColors
    @State private var showTooltip = false
    /// Bumped on each show so a stale auto-hide can't dismiss a newer presentation.
    @State private var tooltipToken = 0
    /// While true, current-step taps are ignored (debounced for `tooltipDuration`).
    @State private var isTapCoolingDown = false
    private let tooltipDuration: TimeInterval = 3

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// iPhone in portrait — needs a stacked top bar and the steps row lifted
    /// out of the bottom bar (the bottom bar can't fit everything in one line).
    private var isIphonePortrait: Bool { !isIpad && !isLandscape }

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

    /// Open-ended parent pour — no target; the bar shows the live count and an
    /// explicit "Done" button (the ring stays an "Add" control).
    private var isOpenEndedStep: Bool {
        pillScanViewModel.isOpenEndedCountStep
    }

    /// "Done" on the open-ended step must not fire with nothing poured, so it's
    /// enabled only once at least one pill has been committed to this step.
    private var isDoneEnabled: Bool {
        currentTotalCount > 0
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
                PillCountTopBar(
                    ndc: pillScanViewModel.currentTransaction?.drug?.ndc ?? "-",
                    drugName: pillScanViewModel.currentTransaction?.drug?.drug_name ?? "-",
                    form: pillScanViewModel.currentTransaction?.drug?.dosage_form ?? "-",
                    strength: pillScanViewModel.currentTransaction?.drug?.strength ?? "-",
                    bucket: pillScanViewModel.currentTransaction?.bucket_id ?? "NORMAL",
                    instructionText: instructionText,
                    isLandscape: isLandscape,
                    isIpad: isIpad,
                    cameraService: cameraService,
                    showGloveIndicator: showGloveIndicator,
                    onBack: onBack
                )

                Spacer()

                // On iPhone portrait the steps row is lifted out of the bottom
                // bar (which can't fit everything in a single line) and shown above it.
                if isIphonePortrait {
                    StepProgressRow(
                        activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                        currentStep: pillScanViewModel.currentControlledStep,
                        onTapCurrentStep: { handleCurrentStepTap() }
                    )
                }

                PillCountBottomBar(
                    activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                    currentStep: pillScanViewModel.currentControlledStep,
                    currentTotalCount: currentTotalCount,
                    targetCount: targetCount,
                    isIpad: isIpad,
                    isLandscape: isLandscape,
                    showSteps: !isIphonePortrait,
                    onTapCurrentStep: { handleCurrentStepTap() },
                    isOpenEndedCountStep: isOpenEndedStep,
                    isDoneEnabled: isDoneEnabled,
                    onShowDetailGrid: onShowDetailGrid,
                    onDone: onAllDone
                )
            }
        }
        // Float the instruction tooltip above the current step icon, anchored to
        // the frame the active StepProgressRow publishes — drawn here so it
        // overflows the bottom bar instead of being clipped inside it.
        .overlayPreferenceValue(CurrentStepAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if showTooltip, !instructionText.isEmpty, let anchor {
                    let rect = proxy[anchor]
                    TooltipBubble(
                        text: instructionText,
                        isIpad: isIpad,
                        background: appColors.primaryBackground.opacity(0.5)
                    )
                    .fixedSize()
                    // Pin the bubble's BOTTOM (its tail tip) just above the icon's
                    // top edge: `.position` centres the view, so measure its height
                    // and lift the centre by half of it plus a clearance gap.
                    .modifier(
                        BottomPinnedAbove(targetTopY: rect.minY, centerX: rect.midX, gap: 16)
                    )
                    // Asymmetric: pops up from the icon with a slight bounce, then
                    // fades out gently while drifting up a touch.
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.7, anchor: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .offset(y: -6))
                    ))
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear { presentTooltip() }
        .onChange(of: pillScanViewModel.currentControlledStep) { _, _ in presentTooltip() }
    }
}

// MARK: - TOOLTIP POSITIONING

/// Places a `.fixedSize` view so its BOTTOM edge sits `gap` points above
/// `targetTopY`, horizontally centred on `centerX`. `.position` centres a view,
/// so we measure its height and offset the centre by half of it.
private struct BottomPinnedAbove: ViewModifier {
    let targetTopY: CGFloat
    let centerX: CGFloat
    let gap: CGFloat

    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { height = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in height = h }
                }
            )
            .position(x: centerX, y: targetTopY - gap - height / 2)
    }
}

// MARK: - TOOLTIP PRESENTATION

private extension PillCountLayout {

    /// User tapped the current step: re-show the tooltip and replay the spoken
    /// instruction. Forced so it always speaks — even if it was just spoken or the
    /// global speech setting is off — because the tap is an explicit "say it again".
    /// Debounced for `tooltipDuration` so rapid taps can't stutter the speech/UI.
    func handleCurrentStepTap() {
        guard !isTapCoolingDown else { return }
        isTapCoolingDown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + tooltipDuration) {
            isTapCoolingDown = false
        }

        presentTooltip()
        if !instructionText.isEmpty {
            SpeechManager.shared.speak(instructionText, force: true)
        }
    }

    /// Show the bubble for `tooltipDuration`; a later call invalidates the
    /// previous auto-hide via the token so the timer can't cut a newer one short.
    func presentTooltip() {
        guard !instructionText.isEmpty else { return }
        tooltipToken += 1
        let token = tooltipToken
        // Springy pop-in with a hint of bounce.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
            showTooltip = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + tooltipDuration) {
            guard token == tooltipToken else { return }
            // Smooth, slightly slower fade-out.
            withAnimation(.easeOut(duration: 0.35)) {
                showTooltip = false
            }
        }
    }
}
