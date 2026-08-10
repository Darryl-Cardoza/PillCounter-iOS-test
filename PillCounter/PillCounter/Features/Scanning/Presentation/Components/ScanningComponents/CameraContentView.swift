//
//  CameraContentView.swift
//  PillCounter
//

import SwiftUI

struct CameraContentView: View {
    @ObservedObject var cameraService: CameraService
    @EnvironmentObject var appColors: AppColors
    @EnvironmentObject var pillScanViewModel: PillScanViewModel
    @State private var isAutoOrManual: Bool = false
    @Environment(\.isLandscape) private var isLandscape

    var isCameraEnabled: Bool

    var body: some View {
        ZStack {
            ZStack(alignment: .bottomTrailing) {
                if cameraService.isAuthorized {
                    CameraView(
                        session: cameraService.getSession(),
                        cameraService: cameraService
                    )
                    .ignoresSafeArea()
                    .task {
                        cameraService.configureInitialOrientation()
                        cameraService.startObservingOrientation()
                        if isCameraEnabled { cameraService.start() }
                    }
                    .onChange(of: isCameraEnabled) { _, enabled in
                        if enabled { cameraService.start() } else { cameraService.stop() }
                    }
                    .onDisappear { cameraService.stop() }
                    .padding(.top, isLandscape ? 0 : 30)

                    if pillScanViewModel.currentControlledStep != .vial {
                        DetectionOverlay(
                            cameraService: cameraService,
                            targetQuantity: {
                                let stepTarget = pillScanViewModel.currentControlledTargetCount ?? 0
                                guard stepTarget > 0 else { return 0 }
                                let alreadyAdded = Int(pillScanViewModel.getTotalCuntForCurrentStep())
                                return max(0, stepTarget - alreadyAdded)
                            }()
                        ).ignoresSafeArea()
//                        TrayOverlay(cameraService: cameraService).ignoresSafeArea()
                    }
                    if pillScanViewModel.currentTransaction?.is_dispense == true {
                        VStack {
                            StepProgressRow(
                                activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                                currentStep: pillScanViewModel.currentControlledStep
                            )
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
            }
        }
    }
}
