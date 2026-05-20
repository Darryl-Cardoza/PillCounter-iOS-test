//
//  PillCountView.swift
//  PillCounter
//
//  Created by HC on 13/11/25.
//

import SwiftUI


struct OPillCountView: View {
    
    // MARK: - ENVIRONMENT
    @Environment(\.isLandscape) private var isLandscape
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject var userViewModel: UserViewModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var pillScanViewModel: PillScanViewModel
    @EnvironmentObject var stockCountViewModel: StockCountViewModel

    // MARK: - STATE MANAGEMENT
    // @StateObject ensures the camera session survives view updates and rotations.
    @StateObject var cameraService = CameraService()
    @StateObject private var locationService = LocationService.shared
    @State private var showZeroCountPopup: Bool = false
    @State private var showNoteOption: Bool = false
    @State private var showConfirmCompletionPopup: Bool = false
    @State private var showTransactionDetailPopup: Bool = false
    @State private var errorMessageOfNote: String?
    @State private var selectedTransactionDetail:
        PillCountTransactionDetailsEntity?

    @State private var addNoteSettings: Bool = AppStorageManager.shared
        .isPillCountingEnabled


    @State private var showTransactionHistory: Bool = true
    @State private var isPaused: Bool = false

    @State private var showFullScreenImage = false
    @State private var fullScreenImage: Image?

    @State private var showDeleteAllTransactionDetailsPopup: Bool = false

    @State private var isAddDisabled: Bool = false
    @State private var showSuccessAnimation: Bool = false
    @State private var lastAddedCount: Int = 0
    
    //Controlled Drug Step
    @State private var showStepCompletionPopup: Bool = false
    @State private var showCountMismatchPopup: Bool = false
    @State private var showSkipContainerPopup: Bool = false
    
    // Vial View State
    @State private var vialCapturedImagePath: String? = nil
    @State private var showCaptureToast = false
    @State private var capturedVialImage: UIImage? = nil
    @State private var showCaptureFlash = false
    
    private var controlledStepInstruction: String {
        let step = pillScanViewModel.currentControlledStep
        let raw  = pillScanViewModel.currentTransaction?.count_type ?? ""

        if raw == CountType.REGULAR.rawValue {
            return L10n.Controlled.regularTargetReverification
        } else {
            return step.displayText
        }
    }

    private var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // MARK: - BODY
    var body: some View {
        ZStack {
            // We use BaseView now because it handles AnyLayout internally,
            // preventing the camera from being destroyed on rotation.
            BaseView(
                topRatio: 0.7,
                topContent: {
                    // Using .id ensures SwiftUI recognizes this as a persistent view
                    ZStack {
                        CameraContentView(
                            cameraService: cameraService,
                            isCameraEnabled: capturedVialImage == nil
                        )
                        .environment(\.colorScheme, .light)

                        if let capturedImage = capturedVialImage {
                            Image(uiImage: capturedImage.fixOrientation())
                                .resizable()
                                .scaledToFill()
                                .ignoresSafeArea()
                                .transition(.opacity)
                        }

                        if showCaptureFlash {
                            Color.white
                                .opacity(0.9)
                                .ignoresSafeArea()
                                .transition(.opacity)
                        }
                    }
                    .id("camera-content")
                },
                bottomContent: {
                    ZStack {
                        if pillScanViewModel.currentControlledStep == .vial {
                            vialControlBottomView
                        } else {
                            controlsContent
                        }
                    }
                
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: isLandscape ? 24 : 24,
                            bottomLeadingRadius: isLandscape ? 24 : 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: isLandscape ? 0 : 24
                        )
                    )
                },
                headerActions: {
                    HStack {
                        Button {
                            router.setRoot(
                                to: .authentication(.login(.dashboard(.dashboardHome)))
                            )
                            cameraService.stop()
                        } label: {
                            PillCountingIconView(
                                imageName: "back_icon",
                                size: 24,
                                padding: 12,
                                foregroundColor: appColors.primary,
                                backgroundColor: .clear,
                                scaleOnIpad: true
                            )
                        }

                        if !isLandscape {
                            Spacer()
                        }
                        
                        if !controlledStepInstruction.isEmpty {
                            PillCountInstructionOverlay(text: controlledStepInstruction)
                                .padding(
                                    .leading,
                                    isLandscape
                                    ? (isIpad ? 220 : 100)
                                    : 0
                                )
                        }

                        Spacer()

                        // Balance space for perfect center alignment
                        Color.clear
                            .frame(width: 48, height: 48)
                    }
                    .padding(.top, isLandscape ? 20 : 60)
                    .padding(.horizontal, 8)
                },
                showBackButton: false,
                showHamburgerMenu: false,
                backgroundColor: Color.clear,
                onBack: {
                    router.setRoot(
                        to: .authentication(.login(.dashboard(.dashboardHome))))
                    cameraService.stop()
                },
            )
            .ignoresSafeArea(.all)

            if pillScanViewModel.showToast  {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image("app_icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)

                        Text(pillScanViewModel.toastMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(10)
                    .padding(.bottom, 32)  // distance from bottom
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: pillScanViewModel.showToast)
            }
            
            if showSuccessAnimation {
                SuccessAnimationView(
                    count: lastAddedCount,
                    color: appColors.secondary
                )
                .allowsHitTesting(false)
                .zIndex(100)
            }

            if cameraService.isPausedDueToInactivity {
                pausedOverlay
            }
        }
        .ignoresSafeArea(.keyboard)
        .onDisappear {
            if pillScanViewModel.isNavigatingToDetailGrid {
                pillScanViewModel.isNavigatingToDetailGrid = false
                return
            }
            // Clean up transaction reference when leaving
            pillScanViewModel.currentTransaction = nil
            pillScanViewModel.currentTransactionTransactionDetails = nil //here
            pillScanViewModel.note = ""
            pillScanViewModel.currentControlledStep = .scan
            pillScanViewModel.currentControlledTargetCount = nil
            cameraService.stop()
        }
        .onTapGesture {
            if !cameraService.isPausedDueToInactivity {
                isPaused = false
                cameraService.resetInactivityTimer()
                cameraService.resumeIfPaused()
            }
        }
        .onAppear {
            cameraService.configureInitialOrientation()
            cameraService.startObservingOrientation()
            initializeTransaction()
            pillScanViewModel.addCurrentOpenPillCount = 0
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                cameraService.start()
            case .background, .inactive:
                cameraService.stop()
            @unknown default:
                break
            }
        }
        .onChange(
            of: cameraService.isPausedDueToInactivity,
            { _, newValue in
                isPaused = newValue
            }
        )
        // MARK: - POPUPS
        .customPopup(isPresented: $showNoteOption) {
            showNoteOptionPopup
        }
        .customPopup(isPresented: $showConfirmCompletionPopup) {
            showConfirmCompletion
        }
        .customPopup(isPresented: $showTransactionDetailPopup) {
            showTransactionDetail
        }
        .customPopup(isPresented: $showZeroCountPopup) {
            zeroCountPopupContent
        }
        .customPopup(
            isPresented: $showDeleteAllTransactionDetailsPopup,
            content: {
                deleteAllTransactionDetailsForCurrentTransaction
            }
        )
        .customPopup(isPresented: $showStepCompletionPopup) {
            showStepCompletion
        }
        .customPopup(isPresented: $showCountMismatchPopup) {
            countMismatchDialog
        }
        .customPopup(isPresented: $showSkipContainerPopup, dismissOnBackgroundTap: false) {
            skipContainerPopup
        }
        .onChange(of: pillScanViewModel.showCompletionPopup) { _, show in
            if show {
                showConfirmCompletionPopup = true
            }
        }
        .onChange(of: pillScanViewModel.currentControlledStep) { _, newStep in
            handleStepVoice(step:newStep)
            
            if newStep == .containerPending &&
                 pillScanViewModel.isContainerPendingZero() {
                  showSkipContainerPopup = true
            }
        }
        .fullScreenCover(isPresented: $showFullScreenImage) {
            FullScreenImageView(
                image: fullScreenImage,
                onDismiss: {
                    showFullScreenImage = false
                }
            )
        }
    }
    
    
    private func handleStepVoice(step: ControlledStep) {
        let text: String

        if  pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue {
            text = L10n.Controlled.regularTargetReverification
        } else {
            text = step.displayText
        }

        SpeechManager.shared.speak(text)
        pillScanViewModel.getAllTransactionDetailsOfTheCurrentTransaction()
    }
}


// MARK: - SUBVIEWS & HELPERS
extension OPillCountView {
    
    private var pausedOverlay: some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 16) {

                    Text(L10n.PillCount.pausedDueToInactivity)
                        .foregroundStyle(appColors.text)

                    Button {
                        cameraService.resumeIfPaused()
                        cameraService.resetInactivityTimer()
                        handleStepVoice(step: pillScanViewModel.currentControlledStep)
                    } label: {
                        Text(L10n.PillCount.resume)
                            .font(.headline)
                            .foregroundColor(Color.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            .background(appColors.primary)
                            .cornerRadius(30)
                    }
                }
            )
    }

    // The bottom control panel with buttons and lists.
    private var controlsContent: some View {
        BottomControlsView(
            isLandscape: isLandscape,
            pillScanViewModel: pillScanViewModel,
            cameraService: cameraService,
            appColors: appColors,
            isAddButtonDisabled: isAddDisabled,
            onAddPill: {
                handleAdd()
            },
            onComplete: {
                handleComplete()
            },
            onReset: {
                showDeleteAllTransactionDetailsPopup = true
            },
            onShowDetailGrid: {
                pillScanViewModel.isNavigatingToDetailGrid = true
                router.navigate(to: .authentication(.login(.dashboard(.pillCount(.scan(.barcode))))))
            },
            onTransactionDetailTapped: { detail in
                selectedTransactionDetail = detail
                showTransactionDetailPopup = true
            },
            showTransactionDetails: $showTransactionHistory,
            isPaused: $isPaused
        )
    }
    
    private var vialControlBottomView: some View {
        VialBottomContentView(
            appColors: appColors,
            isCaptured: capturedVialImage != nil,
            onRedo: {
                handleVialRedo()
            },
            onCapture: {
                handleVialCapture()
            },
            onDone: {
                handleVialDone()
            }
        )
    }

    // Async task to fetch transaction data on load.
    private func initializeTransaction() {
        Task {
            if pillScanViewModel.currentTransaction == nil {
                let txnId = userViewModel.currentTransactionTxnId ?? 0
                await pillScanViewModel.getCurrentTransaction(txnId: txnId)
            }

            await MainActor.run {
                pillScanViewModel.getControlledStep(
                    pillCountTxn: pillScanViewModel.currentTransaction
                )
            }
        }
    }
}


// MARK: - POPUP VIEWS
extension OPillCountView {

    private var deleteAllTransactionDetailsForCurrentTransaction: some View {
        VStack(spacing: 20) {
            Text(L10n.PillCount.confirmDeletion)
                .foregroundStyle(appColors.text)
                .font(.headline)

            Text(L10n.PillCount.deleteAllTransactionsMessage)
            .foregroundStyle(appColors.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            HStack {
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.no,
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 18,
                    iconSize: 0,
                    action: { showDeleteAllTransactionDetailsPopup = false }
                )
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.yes,
                    textColor: Color.white,
                    backgroundColor: appColors.primary,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 18,
                    iconSize: 0,
                    action: {
                        showDeleteAllTransactionDetailsPopup = false
                        pillScanViewModel.deleteAllDetailsOfCurrentTransaction()
                    }
                )
            }
        }
    }

    private var zeroCountPopupContent: some View {
        VStack(spacing: 25) {
            HStack {
                Text(L10n.PillCount.invalidCount)
                    .foregroundStyle(appColors.text)
                    .font(.headline)

                Spacer()

                Button {
                    showZeroCountPopup = false
                } label: {
                    Image(systemName: "xmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(appColors.text)
                }
            }

            Text(L10n.PillCount.zeroPillsMessage)
            .foregroundStyle(appColors.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            PillCountingButton(
                iconName: nil,
                title: L10n.Common.ok,
                textColor: Color.white,
                backgroundColor: appColors.primary,
                borderColor: .clear,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 30,
                horizontalPadding: 40,
                verticalPadding: 14,
                iconSize: 0,
                action: {
                    showZeroCountPopup = false
                }
            )
        }
    }
    
    // Popup showing details of a specific saved count.
    private var showTransactionDetail: some View {
        VStack(spacing: 35) {
            // Header
            HStack {
                Text(
                    String(format: L10n.PillCount.transactionDetail, selectedTransactionDetail?.txn_details_id ?? 0)
                )
                Spacer()
                Button {
                    showTransactionDetailPopup = false
                    selectedTransactionDetail = nil
                } label: {
                    Image(systemName: "xmark")
                        .resizable().scaledToFit().frame(width: 16, height: 16)
                        .foregroundStyle(appColors.text)
                }
            }

            // Content (Image + Count)
            HStack(spacing: 30) {
                if let image = selectedTransactionDetail?.image_path,
                    let loadedImage = PhotoFileManager.shared.loadImage(
                        from: image)
                {
                    loadedImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 120)
                        .clipped()
                        .cornerRadius(12)
                        .onTapGesture {
                            fullScreenImage = loadedImage
                            showFullScreenImage = true
                        }

                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(appColors.text.opacity(0.5), lineWidth: 1)
                        .frame(width: 100, height: 80)
                }

                VStack(spacing: 10) {
                    Text(L10n.PillCount.header).foregroundStyle(appColors.primary)
                    CircleBadge(
                        size: 50,
                        strokeWidth: 0,
                        outerColor: .clear,
                        innerColor: appColors.secondary,
                        text: "\(selectedTransactionDetail?.pill_count ?? 0)",
                        textColor: Color.white,
                        font: .system(size: 18, weight: .bold),
                        isAnimated: false
                    )
                    Text(
                        "\(Formatter.getDateString(from: selectedTransactionDetail?.created_at ?? 0)) "
                            + "\(Formatter.getTimeString(from: selectedTransactionDetail?.created_at ?? 0))"
                    )
                    .foregroundStyle(appColors.text).font(.system(size: 14))
                }
            }

            // Actions (Delete / OK)
            HStack {
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.delete,
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 18,
                    iconSize: 0,
                    action: {
                        showTransactionDetailPopup = false
                        pillScanViewModel
                            .softDeleteCurrentTransactionSelectedTransactionDetail(
                                txnDetailId: selectedTransactionDetail?
                                    .txn_details_id ?? 0
                            )
                    }
                )
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.ok,
                    textColor: Color.white,
                    backgroundColor: appColors.primary,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 18,
                    iconSize: 0,
                    action: { showTransactionDetailPopup = false }
                )
            }
        }
        .frame(width: 300)
    }

    
    private var isTransactionCompleted: Bool {
        if  pillScanViewModel.currentTransaction?.is_from_pms == true {
             true
        } else {
//            pillScanViewModel.getTotalPillCountOfCurrentTransactionByType(type: pillScanViewModel.currentControlledStep)
//            ==  Int32(pillScanViewModel.currentTransaction?.target_count ?? 0)
            true
        }
    }
    
    private var confirmationMessage: String {
        let status =
            isTransactionCompleted
                || router.selectedPillScanningType == .REGULAR
            ? "COMPLETED" : "PENDING"

        let message =
            isTransactionCompleted
                || router.selectedPillScanningType == .REGULAR
            ? "Are you sure you want to mark this transaction as \(status)"
            : "Target not reached. This transaction will be marked as \(status)."

        return message
    }
    // Popup confirming session end if target not met.
    private var showConfirmCompletion: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.confirmCompletionTitle,
            message: confirmationMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: {
                showNoteOption = false
                showConfirmCompletionPopup = false
            },
            onConfirm: {
                showNoteOption = false
                showConfirmCompletionPopup = false
                capturedVialImage = nil
                vialCapturedImagePath = nil
                if pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
                    router.setRoot(to: .authentication(.login(.dashboard(.dashboardHome))))
                    guard let txn = pillScanViewModel.currentTransaction else {
                        return
                    }
                }else{
                    stockCountViewModel.updateCounts(
                        txnId: pillScanViewModel.currentTransaction?.txn_id ,
                        bottleQty: nil,
                        looseQty: pillScanViewModel.addCurrentOpenPillCount
                    )
                    router.setRoot(
                        to: .authentication(
                            .login(
                                .dashboard(
                                    .pillCount(.stockCount(.stockCountBatchDetail))
                                )
                            )
                        )
                    )
                }
                if isTransactionCompleted
                    || router.selectedPillScanningType == .REGULAR
                {
                    Task(
                        priority: .background,
                        operation: {
                            await userViewModel.completeTheSelectedTransaction(
                                txnId: pillScanViewModel.currentTransaction?
                                    .txn_id ?? 0,
                                countType: router.selectedPillScanningType
                                    ?? .FIXED
                            )
                        }
                    )
                }
            }
        )
    }
    
    private var countMismatchDialog: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.countMismatchTitle,
            message: L10n.PillCount.countMismatchMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: {
                showCountMismatchPopup = false
            },
            onConfirm: {
                showNoteOption = true
                showCountMismatchPopup = false
            }
        )
    }
    
    private var showStepCompletion: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.confirmStepCompletionTitle,
            message: L10n.PillCount.confirmStepCompletionMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: {
                showStepCompletionPopup = false
//                capturedVialImage = nil
//                vialCapturedImagePath = nil
            },
            onConfirm: {
                showStepCompletionPopup = false
                pillScanViewModel.handleStepCompletion()
                capturedVialImage = nil
                vialCapturedImagePath = nil
            }
        )
    }

    // Popup for adding a note before saving.
    private var showNoteOptionPopup: some View {
        NotePopupView(
            title: L10n.PillCount.addNote,
            showClose: false,
            text: $pillScanViewModel.note,
            errorMessage: errorMessageOfNote,
            primaryTitle: L10n.Common.save,
            primaryAction: {
                if pillScanViewModel.note.isEmpty {
                    errorMessageOfNote = L10n.PillCount.pleaseAddNote
                    return
                }
                showNoteOption = false
                Task(priority: .background) {
                    pillScanViewModel.updateNoteForCurrentTransaction(
                        txn_id: pillScanViewModel.currentTransaction?.txn_id ?? 0,
                        note: pillScanViewModel.note
                    )
                    await MainActor.run {
                        showConfirmCompletionPopup = true
                    }
                }
            },
            secondaryTitle: pillScanViewModel.currentTransaction?.is_from_pms == false ? L10n.Common.skip : nil,
            secondaryAction: pillScanViewModel.currentTransaction?.is_from_pms == false ? {
                showNoteOption = false
                Task(priority: .background) {
                    await MainActor.run {
                        showConfirmCompletionPopup = true
                    }
                }
                pillScanViewModel.note = ""
            } : {},
            onClose: {
                showNoteOption = false
                showConfirmCompletionPopup = false
            }
        )
    }
    private var skipContainerPopup: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.skipStepTitle,
            message: L10n.PillCount.skipStepMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.skip,
            onCancel: {
                showSkipContainerPopup = false
            },
            onConfirm: {
                showSkipContainerPopup = false
                handleComplete()
            }
        )
    }
}





// View Action button
extension OPillCountView {
    
    private func handleAdd() {
        
        guard !isAddDisabled else { return }
        
        cameraService.resetInactivityTimer()
        cameraService.resumeIfPaused()
        
        guard cameraService.stableCount > 0 else {
            showZeroCountPopup = true
            return
        }
        
        let stepTotal = Int(pillScanViewModel.getTotalCuntForCurrentStep())
        let newTotal = stepTotal + cameraService.stableCount
        let stepTarget = pillScanViewModel.currentControlledTargetCount ?? 0
        
        // Prevent exceeding step target
        if stepTarget > 0 && newTotal > stepTarget {
            pillScanViewModel.showToastMessage(text: L10n.PillCount.totalCountExceedsTarget)
            return
        }
        
        // -------- SAVE TRANSACTION --------
        
        isAddDisabled = true
        lastAddedCount = cameraService.stableCount
        showSuccessAnimation = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            isAddDisabled = false
            showSuccessAnimation = false
        }
        
        
        var savedPath: String? = nil

        if let rawImage = cameraService.captureSnapshotWithOverlays() {
            let user = [
                pillScanViewModel.currentTransaction?.user?.fname,
                pillScanViewModel.currentTransaction?.user?.lname
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

            // Step 1: Compress + grayscale (snapshot already oriented & has overlays)
            guard let processed = rawImage
                .compressedGrayscale(maxWidth: 1080, quality: 1.0)
            else { return }

            // Step 2: Get file size AFTER compression
            guard let data = processed.jpegData(compressionQuality: 0.5) else { return }
            let fileSizeKB = Double(data.count) / 1024.0

            
            let txn = pillScanViewModel.currentTransaction

            let finalImage = processed.addingMetadataOverlay(
                ndc: txn?.drug?.ndc ?? "",
                substituteNdc: txn?.substitueDrug?.ndc ?? "",
                workflowStep: pillScanViewModel.currentControlledStep.rawValue,
                count: cameraService.stableCount,
                targetCount: txn?.target_count,
                lotNo: txn?.lot_no ?? "",
                expiry: txn?.expiry ?? "",
                timestamp: timestamp,
                userInitials: user,
                geolocation: locationService.locationString,
                rx: txn?.rx_no ?? "",
                fileSizeKB: fileSizeKB
            )

            // Step 4: Save
            savedPath = PhotoFileManager.shared.saveImage(finalImage)
        }
        
        
        if pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue{
            pillScanViewModel.addCurrentOpenPillCount += cameraService.stableCount
        }else {
            pillScanViewModel.addTransactionDetailToCurrentTransaction(
                pillCount: Int32(cameraService.stableCount),
                imagePath: savedPath,
                type: pillScanViewModel.currentControlledStep.rawValue
            )
        }
    }
    
    private func handleComplete() {
        let stepTotal = Int(pillScanViewModel.getTotalCuntForCurrentStep())
        let steps = PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction)
        let nextStep = pillScanViewModel.currentControlledStep.next(orderedSteps: steps)
        
        guard pillScanViewModel.canCompleteStep(stepTotal: stepTotal) else {
            if nextStep == nil {
                showCountMismatchPopup = true
            } else {
                pillScanViewModel.showToastMessage(text: L10n.PillCount.countLessThanTarget)
            }
            return
        }
        
        // Last step for normal flowz
        if nextStep == nil {
            if pillScanViewModel.currentTransaction?.is_from_pms != true && pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
                showNoteOption = true
            } else  {
                showConfirmCompletionPopup = true
            }
            return
        }
        
        // Move to next step
        showStepCompletionPopup = true
    }
    
    private func handleVialCapture() {
        guard capturedVialImage == nil else {
            pillScanViewModel.showToastMessage(text: L10n.PillCount.imageAlreadyCaptured)
            return
        }

        guard let image = cameraService.captureSnapshot() else {
            return
        }
        cameraService.stop()
        let normalized = image.normalized()
        capturedVialImage = normalized
        
        showCaptureFlash = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showCaptureFlash = false
        }
        
        cameraService.stop()
        
        if let path = PhotoFileManager.shared.saveImage(normalized) {
            vialCapturedImagePath = path
        }
    }
    
    private func handleVialRedo() {
        capturedVialImage = nil
        vialCapturedImagePath = nil
        cameraService.start()
        cameraService.resetInactivityTimer()
    }
    
    private func handleVialDone() {
        
        let isPmsTxn = pillScanViewModel.currentTransaction?.is_from_pms ?? false
        let steps = PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction)
        let nextStep = pillScanViewModel.currentControlledStep.next(orderedSteps: steps)

        guard let imagePath = vialCapturedImagePath else { return }
    
        // Save vial image
        pillScanViewModel.addOrReplaceVialTransactionDetail(
            imagePath: imagePath
        )
        
        // Normal completion flow
        if addNoteSettings && !isPmsTxn {
            showNoteOption = true
        } else if nextStep == nil {
            showConfirmCompletionPopup = true
        } else {
            showStepCompletionPopup = true
        }
    }
}
