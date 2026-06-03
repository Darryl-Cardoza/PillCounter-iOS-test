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
            if pillScanViewModel.showToast {
                toastView
            }
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
        }.environment(\.colorScheme, .dark)
    }
    // MARK: - Toast

//    // ── OLD bottom toast (kept for reference) ────────────────────────────────
//    private var toastView: some View {
//        VStack {
//            Spacer()
//            HStack(spacing: 10) {
//                Image("app_icon")
//                    .resizable()
//                    .scaledToFit()
//                    .frame(width: 24, height: 24)
//                Text(pillScanViewModel.toastMessage)
//                    .font(.subheadline)
//                    .foregroundColor(.white)
//            }
//            .padding(.horizontal, 14)
//            .padding(.vertical, 10)
//            .background(Color.black.opacity(0.8))
//            .cornerRadius(10)
//            .padding(.bottom, isLandscape ? 10 : showPillCountPanel ? pillCountSheetHeight + 16 : showStockCountPanel ? stockCountSheetHeight + 16 : 32)
//            .transition(.move(edge: .bottom).combined(with: .opacity))
//        }
//        .animation(.easeInOut, value: pillScanViewModel.showToast)
//    }

    private var toastView: some View {
        VStack {
            HStack(spacing: 12) {
                Image("app_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text(pillScanViewModel.toastMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(appColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)

                if !pillScanViewModel.toastAutoClose {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            pillScanViewModel.showToast = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(appColors.text.opacity(0.6))
                            .padding(6)
                            .background(appColors.text.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(appColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 24)
            .padding(.top, isLandscape ? 16 : 60)
            .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: pillScanViewModel.showToast)
    }
}
