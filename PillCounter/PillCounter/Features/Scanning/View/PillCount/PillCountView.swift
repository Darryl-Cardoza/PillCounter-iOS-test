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
    
    // Vial View State
    @State private var vialCapturedImagePath: String? = nil
    @State private var showCaptureToast = false
    @State private var capturedVialImage: UIImage? = nil
    @State private var showCaptureFlash = false

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
                    if pillScanViewModel.currentControlledStep == .vial {
                        vialControlBottomView
                    } else {
                        controlsContent
                    }
                },
                headerActions: {
                    let instruction = pillScanViewModel.currentControlledStep.displayText

                    if !instruction.isEmpty {
                        HStack {
                            Spacer()
                            PillCountInstructionOverlay(text: instruction)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                },
                showBackButton: true,
                showHamburgerMenu: false,
                onBack: {
                    router.setRoot(
                        to: .authentication(.login(.dashboard(.dashboardHome))))
                    cameraService.stop()
                }
            )

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
                .allowsHitTesting(false) // Let user tap through if needed
                .zIndex(100) // Ensure it's on top
            }

            if cameraService.isPausedDueToInactivity {
                pausedOverlay
            }
        }
        .ignoresSafeArea(.keyboard)
        .onDisappear {
            // Clean up transaction reference when leaving
//            pillScanViewModel.currentTransaction = nil
//            pillScanViewModel.currentTransactionTransactionDetails = nil //here
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
        .onChange(of: pillScanViewModel.showCompletionPopup) { _, show in
            if show {
                showConfirmCompletionPopup = true
            }
        }
        .onChange(of: pillScanViewModel.currentControlledStep) { _, newStep in
            handleStepVoice(newStep)
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
    
    private func handleStepVoice(_ step: ControlledStep) {
        SpeechManager.shared.speak(step.displayText)
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

                    Text("COUNTING PAUSED DUE TO INACTIVITY.")
                        .foregroundStyle(appColors.text)

                    Button {
                        cameraService.resumeIfPaused()
                        cameraService.resetInactivityTimer()
                        handleStepVoice(pillScanViewModel.currentControlledStep)
                    } label: {
                        Text("Resume")
                            .font(.headline)
                            .foregroundColor(Color.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            .background(appColors.secondary)
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
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(appColors.secondaryBackground)
        )
    }

//    // Async task to fetch transaction data on load.
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
            Text("CONFIRM DELETION")
                .foregroundStyle(appColors.text)
                .font(.headline)

            Text(
                "Are you sure you want to delete all the transactions for this current transaction."
            )
            .foregroundStyle(appColors.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            HStack {
                PillCountingButton(
                    iconName: nil,
                    title: "NO",
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
                    title: "YES ",
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
                Text("INVALID COUNT")
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

            Text("Cannot add a batch with 0 pills.\nPlease ensure pills are detected by the camera.")
            .foregroundStyle(appColors.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            PillCountingButton(
                iconName: nil,
                title: "OK",
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
                    "Transaction detail \(selectedTransactionDetail?.txn_details_id ?? 0)"
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
                    Text("PILLS COUNT").foregroundStyle(appColors.primary)
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
                    title: "DELETE",
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
                    title: "OK",
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

//    private var isTransactionCompleted: Bool {
//        pillScanViewModel.getTotalPillCountOfCurrentTransaction()
//            == (pillScanViewModel.currentTransaction?.target_count ?? 0)
//    }
    
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
            title: "Confirm Completion",
            message: confirmationMessage,
            cancelButtonText: "CANCEL",
            confirmButtonText: "OK",
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

                    Hl7ServiceController.shared.sendTransaction(txn)
                
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
            title: "Count Mismatch",
            message: "The counted quantity does not match the target count. Do you want to proceed?",
            cancelButtonText: "CANCEL",
            confirmButtonText: "OK",
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
            title: "Confirm Step Completion",
            message: "Are you sure you want to complete this step?",
            cancelButtonText: "CANCEL",
            confirmButtonText: "OK",
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
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Text("ADD NOTE").foregroundStyle(appColors.text)
                Spacer()
                Button {
                    showNoteOption = false
                    showConfirmCompletionPopup = false
                } label: {
                    Image(systemName: "xmark")
                        .resizable().scaledToFit().frame(width: 16, height: 16)
                        .foregroundStyle(appColors.text)
                }
            }

            PillCounterTextEditor(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $pillScanViewModel.note
            )

            if let errorMessageOfNote = errorMessageOfNote {
                Text(errorMessageOfNote).foregroundStyle(Color.red).padding(
                    .top,
                    -20
                )
            }

            HStack {
                if pillScanViewModel.currentTransaction?.is_from_pms == false{
                    PillCountingButton(
                        iconName: nil,
                        title: "SKIP",
                        textColor: appColors.text,
                        backgroundColor: appColors.primaryBackground,
                        borderColor: appColors.primary,
                        font: .system(size: 12, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 32,
                        verticalPadding: 14,
                        iconSize: 0,
                        action : {
                            showNoteOption = false
                            Task(priority: .background) {
                                await MainActor.run {
                                    // Controlled drug → move to next step
                                    if pillScanViewModel.currentTransaction?.is_from_pms == true {
                                        pillScanViewModel.handleStepCompletion()
                                    } else {
                                        // Normal drug → completion popup
                                        showConfirmCompletionPopup = true
                                    }
                                }
                            }
                        }
                     )
                }
                PillCountingButton(
                    iconName: nil,
                    title: "SAVE",
                    textColor: appColors.text,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 12, weight: .regular),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: {
                        if pillScanViewModel.note.isEmpty {
                            errorMessageOfNote = "Please add a note"
                            return
                        }

                        showNoteOption = false

                        Task(priority: .background) {
                            pillScanViewModel.updateNoteForCurrentTransaction(
                                txn_id: pillScanViewModel.currentTransaction?.txn_id ?? 0,
                                note: pillScanViewModel.note
                            )

                            await MainActor.run {
                                // Controlled drug → move to next step
//                                if pillScanViewModel.currentTransaction?.is_from_pms == true {
//                                    pillScanViewModel.handleStepCompletion()
//                                      
//                                } else {
                                    // Normal drug → completion popup
                                    showConfirmCompletionPopup = true
//                                }z
                            }
                        }
                    }
                )
            }
        }
        .frame(width: 250)
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
            pillScanViewModel.showToastMessage(text:"Total transaction count exceeds target." )
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
        
//        var savedPath: String? = nil
//        if let compositeImage = cameraService.captureSnapshotWithOverlays() {
//            savedPath = PhotoFileManager.shared.saveImage(compositeImage)
//        }
        
        var savedPath: String? = nil

        if let rawImage = cameraService.captureSnapshotWithOverlays() {
            let user = [
                pillScanViewModel.currentTransaction?.user?.fname,
                pillScanViewModel.currentTransaction?.user?.lname
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

            // Step 1: Process image
            guard let processed = rawImage
                .compressedGrayscale(maxWidth: 1080, quality: 0.5)
            else { return }

            // Step 2: Get file size FIRST
            guard let data = processed.jpegData(compressionQuality: 0.5) else { return }
            let fileSizeKB = Double(data.count) / 1024.0

            // Step 3: Add overlay
            let finalImage = processed.addingMetadataOverlay(
                ndc: pillScanViewModel.currentTransaction?.drug?.ndc ?? "",
                user: user,
                count: cameraService.stableCount,
                rx: pillScanViewModel.currentTransaction?.rx_no ?? "",
                location: locationService.locationString,
                timestamp: timestamp,
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
                pillScanViewModel.showToastMessage(text:"Count is less than target.")
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
            pillScanViewModel.showToastMessage(text: "Image already captured. Tap Redo to capture again.")
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

        guard let imagePath = vialCapturedImagePath else {
            pillScanViewModel.showToastMessage(text:"Capture the image first." )
            return
        }
    
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
