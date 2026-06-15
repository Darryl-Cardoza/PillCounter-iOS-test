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
    private var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }


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

            // ── Vial captured still (full screen) ─────────────────────────────
            // During the vial step, once the operator captures the vial image we show
            // that still full-screen, fully covering the live feed (opaque black
            // backing so no camera background bleeds through). "Redo" clears
            // capturedVialImage and this overlay disappears, revealing the live feed.
            if pillScanViewModel.currentControlledStep == .vial,
               let vialImage = pillScanViewModel.capturedVialImage {
                // Match the live camera framing exactly: a full-bleed container
                // (GeometryReader sized to the whole screen) with the still filling it
                // via scaledToFill + clipped — same as the preview's .resizeAspectFill.
                // This keeps the overlaid UI (header, controls) aligned identically
                // whether the live feed or the captured still is showing.
                GeometryReader { geo in
                    Image(uiImage: vialImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
                .allowsHitTesting(false)
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
                    // ── Portrait: instruction centered independently ──
                    if !isLandscape && !instructionText.isEmpty {
                        PillCountInstructionOverlay(text: instructionText)
                            .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 0) {
                        // Back button — always leading
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

                        if isLandscape {
                            if showPillCountPanel   {
                                // showPillCountPanel true: back | 16 | instruction | 16 | glove | Spacer
                                Color.clear.frame(width: 220, height: 1)
                                if !instructionText.isEmpty {
                                    PillCountInstructionOverlay(text: instructionText)
                                }
                                if showPillDetectionUI && cameraService.isGloveDetectionEnabled {
                                    Color.clear.frame(width: isIpad ? 200 : 50, height: 1)
                                    GloveStatusIndicator(cameraService: cameraService)
                                }
                                Spacer()
                            } else {
                                Spacer()
                                // showPillCountPanel false: back | Spacer | instruction | 16 | glove
                                if !instructionText.isEmpty {
                                    PillCountInstructionOverlay(text: instructionText)
                                        .frame(maxWidth: .infinity).frame(alignment: .center)
                                }
                            }
                        } else {
                            // Portrait: glove pinned trailing, instruction handled by ZStack
                            Spacer()
                            if showPillDetectionUI && cameraService.isGloveDetectionEnabled {
                                GloveStatusIndicator(cameraService: cameraService)
                            } else {
                                Color.clear.frame(width: 48, height: 48)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
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
