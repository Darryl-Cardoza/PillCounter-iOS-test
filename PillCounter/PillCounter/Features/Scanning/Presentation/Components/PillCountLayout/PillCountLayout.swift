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
    let isDispense: Bool
    let isLandscape: Bool
    let isAddDisabled: Bool
    /// Step instruction text — hosted in the top bar (old header content moved here).
    let instructionText: String
    /// Whether the glove-status indicator should show (old header content moved here).
    let showGloveIndicator: Bool
    /// True when the user is counting open/loose pills — overrides the targetVerification
    /// tooltip and voice label from "Count Prescribed Quantity" to "Count Open Pills".
    let isOpenPillScanMode: Bool

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
    /// While true, step taps are ignored (debounced for `tooltipDuration`).
    @State private var isTapCoolingDown = false
    /// The step the tooltip is currently anchored to and speaking for. Defaults to
    /// the current step (used for the auto-show on appear / step change); updated to
    /// whichever step the user taps.
    @State private var tooltipStep: ControlledStep?
    private let tooltipDuration: TimeInterval = 3

    /// Instruction text for whichever step the tooltip is presenting. Uses the host's
    /// `instructionText` when showing the current step in open-pill mode (so the label
    /// reads "Count Open Pills" instead of "Count Prescribed Quantity").
    private var tooltipText: String {
        guard let step = tooltipStep else { return instructionText }
        if isOpenPillScanMode && step == .targetVerification
            && step == pillScanViewModel.currentControlledStep {
            return instructionText
        }
        return step.displayText
    }

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Any device in portrait — the steps row is lifted out of the bottom bar
    /// (the bottom bar can't fit everything in one line in portrait) and shown
    /// above it. Applies to both iPhone and iPad portrait.
    private var isPortrait: Bool { !isLandscape }

    // ── Data mirrors BottomControlsView so the displayed numbers are identical ──

    /// Target for the current step (0 when there is no meaningful target, e.g. REGULAR).
    private var targetCount: Int {
        if isOpenPillScanMode || pillScanViewModel.currentTransaction?.is_dispense == false {
            return 0
        } else if pillScanViewModel.currentTransaction?.is_from_pms == true {
            return pillScanViewModel.currentControlledTargetCount ?? 0
        } else {
            return pillScanViewModel.currentControlledTargetCount ?? 0
        }
    }

    /// Total committed count for the current transaction / step.
    private var currentTotalCount: Int {
        if isOpenPillScanMode || pillScanViewModel.currentTransaction?.is_dispense == false {
            return pillScanViewModel.addCurrentOpenPillCount
        } else if pillScanViewModel.currentTransaction?.is_from_pms == true {
            return Int(pillScanViewModel.getTotalCuntForCurrentStep())
        } else {
            return pillScanViewModel.getTotalPillCountOfCurrentTransaction()
        }
    }

    /// True once the committed total reaches the step target — ring shows "All Done".
    private var isTargetReached: Bool {
        targetCount > 0 && currentTotalCount >= targetCount
    }

    private var isFixed: Bool {
        pillScanViewModel.currentTransaction?.is_dispense == true
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
            .zIndex(10000)

            // ── Top + bottom bars ──────────────────────────────────────────
            VStack(spacing: 0) {
                PillCountTopBar(
                    ndc: pillScanViewModel.currentDrug?.ndc ?? "-",
                    drugName: pillScanViewModel.currentDrug?.drug_name ?? "-",
                    drugImagePath: pillScanViewModel.currentDrug?.drug_image,
                    form: pillScanViewModel.currentDrug?.dosage_form ?? "-",
                    strength: pillScanViewModel.currentDrug?.strength ?? "-",
                    bucket: pillScanViewModel.currentTransaction?.bucket_id
                        ?? pillScanViewModel.currentStockTxn?.bucket_id ?? "NORMAL",
                    instructionText: instructionText,
                    isLandscape: isLandscape,
                    isIpad: isIpad,
                    cameraService: cameraService,
                    showGloveIndicator: showGloveIndicator,
                    onBack: onBack
                )

                Spacer()

                // In portrait (iPhone or iPad) the steps row is lifted out of the
                // bottom bar (which can't fit everything in a single line) and
                // shown above it.
                if isPortrait {
                    StepProgressRow(
                        activeSteps: isOpenPillScanMode ? [.scan, .targetVerification] : PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                        currentStep: pillScanViewModel.currentControlledStep,
                        onTapStep: { handleStepTap($0) }
                    )
                }

                PillCountBottomBar(
                    activeSteps: isOpenPillScanMode ? [.scan, .targetVerification] : PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                    currentStep: pillScanViewModel.currentControlledStep,
                    currentTotalCount: currentTotalCount,
                    targetCount: targetCount,
                    isIpad: isIpad,
                    isLandscape: isLandscape,
                    showSteps: !isPortrait,
                    onTapStep: { handleStepTap($0) },
                    isOpenEndedCountStep: isOpenEndedStep,
                    isRegularCountType: isOpenPillScanMode || pillScanViewModel.currentTransaction?.is_dispense == false,
                    isDoneEnabled: isDoneEnabled,
                    onShowDetailGrid: onShowDetailGrid,
                    onDone: onAllDone
                )
            }
        }
        // Float the instruction tooltip above the tapped (or current) step icon,
        // anchored to the per-step frames the active StepProgressRow publishes —
        // drawn here so it overflows the bottom bar instead of being clipped inside it.
        .overlayPreferenceValue(StepAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if showTooltip, !tooltipText.isEmpty,
                   let step = tooltipStep, let anchor = anchors[step] {
                    let rect = proxy[anchor]
                    TooltipBubble(
                        text: tooltipText,
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
        .onAppear { presentTooltip(for: pillScanViewModel.currentControlledStep) }
        .onChange(of: pillScanViewModel.currentControlledStep) { _, step in presentTooltip(for: step) }
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

    /// User tapped a step (any step, not just the current one): float that step's
    /// tooltip above its icon and replay its spoken instruction. Forced so it always
    /// speaks — even if it was just spoken or the global speech setting is off —
    /// because the tap is an explicit "say it again". Debounced for `tooltipDuration`
    /// so rapid taps can't stutter the speech/UI.
    func handleStepTap(_ step: ControlledStep) {
        guard !isTapCoolingDown else { return }
        isTapCoolingDown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + tooltipDuration) {
            isTapCoolingDown = false
        }

        presentTooltip(for: step)
        let text: String
        if isOpenPillScanMode && step == .targetVerification
            && step == pillScanViewModel.currentControlledStep {
            text = instructionText
        } else {
            text = step.displayText
        }
        if !text.isEmpty {
            SpeechManager.shared.speak(text, force: true)
        }
    }

    /// Anchor the bubble to `step` and show it for `tooltipDuration`; a later call
    /// invalidates the previous auto-hide via the token so the timer can't cut a
    /// newer one short.
    func presentTooltip(for step: ControlledStep) {
        tooltipStep = step
        guard !tooltipText.isEmpty else { return }
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
