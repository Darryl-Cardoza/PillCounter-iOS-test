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
    /// True while scanning the RX label barcode (ScanType.rx_label) — the .scan step's
    /// top and bottom bars are both suppressed here since there's nothing step-relevant
    /// to show yet (unlike scanning the container/stock barcode, where the steps row
    /// is useful).
    let isRxLabelScan: Bool

    let onBack: () -> Void
    let onAdd: () -> Void
    let onAllDone: () -> Void
    let onShowDetailGrid: () -> Void
    /// Reset the current transaction — hard-deletes its counts/images and
    /// restarts it from the scan step.
    var onReset: () -> Void = {}

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

    /// Vial step — swaps the movable count ring for the redo/capture/done controls
    /// and suppresses the count/target parts of the bottom bar (view via `hidesCountUI`
    /// on `PillCountBottomBar`).
    private var isVialStep: Bool { pillScanViewModel.currentControlledStep == .vial }

    /// Raw barcode-scan phase (before RX resolves) — no drug is known yet, so the
    /// top bar (drug name / NDC / etc.) is also suppressed, unlike vial.
    private var isScanStep: Bool { pillScanViewModel.currentControlledStep == .scan }

    /// Steps with no drug/target/count data yet — vial (capture only) and the raw
    /// barcode-scan phase (before RX resolves). Both suppress the count ring and
    /// show only the bottom bar's steps row (via `hidesCountUI` on `PillCountBottomBar`).
    private var isBarOnlyStep: Bool { isVialStep || isScanStep }

    /// The effectively-current transaction. During `.scan`, `currentTransaction`
    /// is often still nil: the RX-label decode path hasn't assigned it yet (falls
    /// back to `fetchedRxTransaction`, populated at decode time), and the
    /// dashboard-tap path (.barcode/.resumeCount scanType) never assigns it until
    /// a barcode is matched either — that path already fetched the txn into
    /// `selectedTransaction` (see `startDispenseCount`). Single source so
    /// `activeSteps`, `topBarDrug`, and the top bar's bucket_id all resolve the
    /// same transaction instead of each re-deriving this fallback chain.
    private var resolvedTransaction: PillCountTransactionEntity? {
        pillScanViewModel.currentTransaction
            ?? pillScanViewModel.fetchedRxTransaction
            ?? pillScanViewModel.selectedTransaction
    }

    /// `.scan` with no transaction resolvable anywhere yet (fresh `.barcode`/
    /// `.stockCount` scan, nothing selected) — nothing real to show, so bars are
    /// suppressed instead of showing the resolver's fabricated placeholder steps.
    /// Open-pill scan mode included: its `.scan` step is always pre-barcode (drug
    /// found flips the step straight to `.targetVerification` — see
    /// `handleDrugFoundState`), so there's never a drug to show in the top bar here.
    private var isUnresolvedScan: Bool {
        isScanStep && resolvedTransaction == nil
    }

    /// Suppresses both PillCountTopBar and PillCountBottomBar during `.scan` when
    /// there's nothing real to show them: scanning the RX label itself (that scan
    /// IS what resolves the transaction — the legacy header in UnifiedCameraLayout
    /// covers this screen instead), or no transaction resolved at all yet (fresh
    /// .barcode/.stockCount scan).
    private var hidesTopAndBottomBars: Bool { isScanStep && (isRxLabelScan || isUnresolvedScan) }

    /// Steps row source — same computation everywhere so `.scan` shows the same
    /// drug-specific steps that show once the transaction resolves, instead of a
    /// separate/duplicated fetch.
    private var activeSteps: [ControlledStep] {
        if isOpenPillScanMode {
            return [.scan, .targetVerification]
        }
        return PillCountingStepResolver.getActiveSteps(txn: resolvedTransaction)
    }

    /// Top bar drug info source. Same nil-window as `activeSteps` — see its comment.
    private var topBarDrug: DrugMasterEntity? {
        pillScanViewModel.currentDrug ?? resolvedTransaction?.drug
    }

    /// Any device in portrait — the steps row is lifted out of the bottom bar
    /// (the bottom bar can't fit everything in one line in portrait) and shown
    /// above it. Applies to both iPhone and iPad portrait.
    private var isPortrait: Bool { !isLandscape }

    // ── Data mirrors BottomControlsView so the displayed numbers are identical ──

    /// Target for the current step (0 when there is no meaningful target, e.g. REGULAR).
    private var targetCount: Int {
        if isOpenPillScanMode || resolvedTransaction?.is_dispense == false {
            return 0
        } else if resolvedTransaction?.is_from_pms == true {
            return pillScanViewModel.currentControlledTargetCount ?? 0
        } else {
            return pillScanViewModel.currentControlledTargetCount ?? 0
        }
    }

    /// Total committed count for the current transaction / step.
    private var currentTotalCount: Int {
        if isOpenPillScanMode || resolvedTransaction?.is_dispense == false {
            return pillScanViewModel.addCurrentOpenPillCount
        } else if resolvedTransaction?.is_from_pms == true {
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
        resolvedTransaction?.is_dispense == true
    }

    /// Reset is offered only while there is something to undo. Straight after a reset
    /// the transaction is still PARTIAL (so `canResetCurrentTransaction` stays true)
    /// but every detail row and image is already gone — nothing left to wipe.
    private var hasCountsToReset: Bool {
        if isOpenPillScanMode {
            return !pillScanViewModel.pendingOpenBottleImages.isEmpty
        }
        return !(pillScanViewModel.currentTransactionTransactionDetails ?? []).isEmpty
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
        // Computed once per body pass — PillCountingStepResolver.getActiveSteps
        // does a real Core Data fetch, and both the lifted-out StepProgressRow
        // (portrait) and PillCountBottomBar below read the same steps list.
        let activeSteps = activeSteps
        ZStack {
            if isVialStep {
                // ── Vial capture controls, trailing edge, landscape only. In
                // portrait they're stacked directly above the bottom bar below
                // (single VStack, so they can't overlap it). ──
                if isLandscape {
                    HStack {
                        Spacer()
                        vialControlBottomView
                            .padding(.trailing, isIpad ? 24 : 14)
                    }
                }
            } else if !isBarOnlyStep {
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
            }

            // ── Top + bottom bars ──────────────────────────────────────────
            VStack(spacing: 0) {
                // Shown for every step except the RX-label scan itself, which has
                // no confirmed drug yet — the legacy header there covers it instead.
                if !hidesTopAndBottomBars {
                PillCountTopBar(
                    ndc: topBarDrug?.ndc ?? "-",
                    drugName: topBarDrug?.drug_name ?? "-",
                    drugImagePath: topBarDrug?.drug_image,
                    form: topBarDrug?.dosage_form ?? "-",
                    strength: topBarDrug?.strength ?? "-",
                    bucket: resolvedTransaction?.bucket_id
                        ?? pillScanViewModel.currentStockTxn?.bucket_id ?? "NORMAL",
                    instructionText: instructionText,
                    isLandscape: isLandscape,
                    isIpad: isIpad,
                    cameraService: cameraService,
                    showGloveIndicator: showGloveIndicator,
                    onBack: onBack
                )
                }

                Spacer()

                // In portrait (iPhone or iPad) the steps row is lifted out of the
                // bottom bar (which can't fit everything in a single line) and
                // shown above it.
                if isPortrait && !isBarOnlyStep {
                    StepProgressRow(
                        activeSteps: activeSteps,
                        currentStep: pillScanViewModel.currentControlledStep,
                        onTapStep: { handleStepTap($0) }
                    )
                }

                // Vial controls stacked directly above the bar in portrait — same
                // VStack as the bar below, so Spacer-driven bottom pinning can't
                // make them overlap.
                if isVialStep && isPortrait {
                    vialControlBottomView
                        .padding(.bottom, isIpad ? 24 : 14)
                }

                if !hidesTopAndBottomBars {
                PillCountBottomBar(
                    activeSteps: activeSteps,
                    currentStep: pillScanViewModel.currentControlledStep,
                    currentTotalCount: currentTotalCount,
                    targetCount: targetCount,
                    isIpad: isIpad,
                    isLandscape: isLandscape,
                    showSteps: !isPortrait || isBarOnlyStep,
                    onTapStep: { handleStepTap($0) },
                    isOpenEndedCountStep: isOpenEndedStep,
                    isRegularCountType: isOpenPillScanMode || resolvedTransaction?.is_dispense == false,
                    isDoneEnabled: isDoneEnabled,
                    hidesCountUI: isBarOnlyStep,
                    isResetEnabled: (isOpenPillScanMode || pillScanViewModel.canResetCurrentTransaction)
                        && hasCountsToReset,
                    onShowDetailGrid: onShowDetailGrid,
                    onDone: onAllDone,
                    onReset: onReset
                )
                }
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

    /// Redo / capture / done controls for the vial step. `VialBottomContentView`
    /// reads `pillScanViewModel` / `cameraService` as environment objects, so both
    /// are injected here even though this view already holds them as plain lets.
    private var vialControlBottomView: some View {
        VialBottomContentView()
            .environmentObject(pillScanViewModel)
            .environmentObject(cameraService)
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
