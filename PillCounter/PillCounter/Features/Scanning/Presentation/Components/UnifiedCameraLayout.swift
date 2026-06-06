//
//  UnifiedCameraLayout.swift
//  PillCounter
//
//  Full-screen camera ZStack: preview, ML overlays, header, toasts, inactivity overlay.
//

import SwiftUI

struct UnifiedCameraLayout: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    let cameraService: CameraService
    let showPillCountPanel: Bool
    let pillCountSheetHeight: CGFloat
    let showStockCountPanel: Bool
    let stockCountSheetHeight: CGFloat
    let isLandscape: Bool
    let instructionText: String
    let showPillDetectionUI: Bool
    let onBack: () -> Void
    let onResume: () -> Void

    var body: some View {
        ZStack {
            // ── Camera preview ────────────────────────────────────────────────
            if cameraService.isAuthorized {
                CameraView(session: cameraService.getSession(), cameraService: cameraService)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                NoCameraPermissionView()
            }

            if showPillDetectionUI {
                DetectionOverlay(cameraService: cameraService)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                TrayOverlay(cameraService: cameraService)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // ── Pill count ring (barcode-scan phase only) ─────────────────
                if !showPillCountPanel {
                    PillCountRingView(count: cameraService.stableCount, isLandscape: isLandscape)
                }
            }

            // ── Loading spinner ───────────────────────────────────────────────
            if pillScanViewModel.isCheckingNdc || stockCountViewModel.isLoading || !cameraService.isAuthorized {
                Color.black.opacity(0.5).ignoresSafeArea()
                PillCountingLoader()
            }

            // ── Inactivity pause overlay ──────────────────────────────────────
            if cameraService.isPausedDueToInactivity {
                inactivityOverlay
            }

            // ── Header row ────────────────────────────────────────────────────
            VStack {
                ZStack {
                    // Back button pinned to leading edge
                    HStack {
                        Button(action: onBack) {
                            PillCountingIconView(
                                imageName: "back_icon",
                                size: 24,
                                padding: 12,
                                foregroundColor: appColors.primary,
                                backgroundColor: .clear,
                                scaleOnIpad: true
                            )
                        }
                        Spacer()
                    }

                    // Instruction centered independently
                    if !instructionText.isEmpty {
                        PillCountInstructionOverlay(text: instructionText)
                            .frame(maxWidth: .infinity)
                    }
                    Spacer()
                    if showPillDetectionUI && cameraService.isGloveDetectionEnabled {
                        GloveStatusIndicator(cameraService: cameraService)
                    } else {
                        Color.clear.frame(width: 48, height: 48)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, isLandscape ? 10 : 40)
                Spacer()
                
                Color.clear.frame(height: showPillCountPanel ? pillCountSheetHeight : showStockCountPanel ? stockCountSheetHeight : 0)
            }

            // ── Controlled step row ───────────────────────────────────────────
            if showPillCountPanel,
               pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
               controlledStepRow
            }

            // ── Toast ─────────────────────────────────────────────────────────
            // Toasts are shown via the global ToastManager (see PillScanViewModel
            // .showToastMessage). No local toast here to avoid duplicate toasts.
        }
        .ignoresSafeArea()
        .onTapGesture {
            if cameraService.isPausedDueToInactivity { onResume() }
        }
    }

    // MARK: - Sub-views

    private var inactivityOverlay: some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 16) {
                    Text(L10n.PillCount.pausedDueToInactivity)
                        .foregroundStyle(appColors.text)
                    Button(action: onResume) {
                        Text(L10n.PillCount.resume)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            .background(appColors.primary)
                            .cornerRadius(30)
                    }
                }
            )
    }

    private var controlledStepRow: some View {
        VStack(spacing: 0) {
            if isLandscape {
                Spacer()
                HStack {
                    ControlledStepRow(
                        activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                        currentStep: pillScanViewModel.currentControlledStep
                    )
                    .padding(.bottom, 8)
                    Spacer().frame(width: 300)
                }
            } else {
                Spacer()
                ControlledStepRow(
                    activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                    currentStep: pillScanViewModel.currentControlledStep
                )
                Spacer().frame(height: pillCountSheetHeight)
            }
        }
    }
}
