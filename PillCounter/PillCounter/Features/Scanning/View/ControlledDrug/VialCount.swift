//
//  VialCount.swift
//  PillCounter
//
//  Created by Bhushan Patil on 05/03/26.
//
//
//
//  VialCaptureView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 05/03/26.
//

import SwiftUI
import CoreData

struct VialCaptureView: View {

    @EnvironmentObject var pillScanViewModel: PillScanViewModel
    @EnvironmentObject var userViewModel: UserViewModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var appColors: AppColors

    @StateObject private var cameraService = CameraService()

    var body: some View {

        ZStack {

            // 1. Full screen camera
            CameraView(
                session: cameraService.getSession(),
                cameraService: cameraService
            )
            .ignoresSafeArea()

            // 2. Top: back button + instruction
            VStack(spacing: 0) {

                topBar

                Spacer()

                // 3. Bottom: step row + capture button
                VStack(spacing: 0) {
                    ControlledStepRow(
                        activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                        currentStep: .vial
                    )
                    
                    captureButton
                }
            }
        }
        .task {
            cameraService.configureInitialOrientation()
            cameraService.startObservingOrientation()
            cameraService.start()
        }
        .onDisappear {
            cameraService.stop()
            pillScanViewModel.currentControlledStep = .scan
        }
        .onAppear{
//            if userViewModel.currentTransactionTxnId == nil {
//                pillScanViewModel.resetScanningState()
//            }
            initializeTransaction()
        }
    }
    
    
    private func initializeTransaction() {
        Task {

            if pillScanViewModel.currentTransaction == nil {
                let txnId = userViewModel.currentTransactionTxnId ?? 0
                await pillScanViewModel.getCurrentTransaction(txnId: txnId)
            }

            pillScanViewModel.getControlledStep(
                pillCountTxn: pillScanViewModel.currentTransaction
            )
        }
    }
}


// MARK: - Top Bar

extension VialCaptureView {

    var topBar: some View {

        HStack(spacing: 8) {

            // Back button
           backButton
            // Instruction label
            PillCountInstructionOverlay(
                text: pillScanViewModel.currentControlledStep.displayText.isEmpty
                    ? "Capture photo of counted pills vial"
                    : pillScanViewModel.currentControlledStep.displayText
            )

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    private var backButton: some View {
        Button {
            router.setRoot(
                to: .authentication(.login(.dashboard(.dashboardHome))))
        } label: {
            HStack {
                Image("back_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .padding(12)
                    .background(Color.clear)
                    .clipShape(Circle())

            }
        }
    }
}



// MARK: - Capture Button

extension VialCaptureView {

    var captureButton: some View {

        HStack {
            Spacer()
            Button {
                captureVialImage()
            } label: {
                Circle()
                    .fill(appColors.primary)
                    .frame(width: 75, height: 75)
                    .overlay(
                        Image("vial_step5")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.white)
                    )
                    .shadow(
                        color: appColors.secondary.opacity(0.40),
                        radius: 10, x: 0, y: 4
                    )
            }
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.bottom, 10)
    }
}

// MARK: - Capture Logic

extension VialCaptureView {

    func captureVialImage() {


        if let image = cameraService.captureSnapshotWithOverlays(),
           let path = PhotoFileManager.shared.saveImage(image) {

            pillScanViewModel.addTransactionDetailToCurrentTransaction(
                pillCount: 0,
                imagePath: path,
                type: ControlledStep.vial.rawValue
            )

            // Move workflow forward
            pillScanViewModel.handleStepCompletion()

            // Navigate after step change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                router.navigateBack()
            }
        }
    }
}
