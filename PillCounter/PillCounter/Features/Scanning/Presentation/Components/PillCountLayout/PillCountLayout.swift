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

                Spacer()

                PillCountBottomBar(
                    activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                    currentStep: pillScanViewModel.currentControlledStep,
                    currentTotalCount: currentTotalCount,
                    targetCount: targetCount,
                    isIpad: isIpad,
                    isLandscape: isLandscape,
                    onShowDetailGrid: onShowDetailGrid
                )
            }
        }
    }
}
