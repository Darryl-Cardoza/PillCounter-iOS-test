//
//  UnifiedCameraView.swift
//  PillCounter
//
//  Route owner: composes all camera layers and wires state to sub-views.
//
//  State machine
//  ─────────────
//  .scanning    → camera live, barcode scanning active
//  .rxDetected  → barcode scanning stopped, RX bottom sheet shown
//
//  Sub-views (in Components/)
//  ───────────────────────────
//  UnifiedCameraLayout          full-screen camera + overlays + header
//  PillCountRingView            animated count ring shown before pill-count panel opens
//  UnifiedCameraBarcodePopups   NDC / barcode / stock-count popup content (extension)
//  UnifiedCameraPillCountPopups pill-count-phase popup content (extension)


import AVFoundation
import SwiftUI

// MARK: - State Machine

enum UnifiedCameraState: Equatable {
    case scanning
    case rxDetected
}

// MARK: - Root View

struct UnifiedCameraView: View {

    // ── Dependencies ──────────────────────────────────────────────────────────
    @EnvironmentObject var router: Router
    @EnvironmentObject var appColors: AppColors
    @EnvironmentObject var pillScanViewModel: PillScanViewModel
    @EnvironmentObject var userViewModel: UserViewModel
    @EnvironmentObject var stockCountViewModel: StockCountViewModel

    // ── Navigation parameter ──────────────────────────────────────────────────
    let currentScanType: ScanType
    @State var scanType: ScanType = .barcode

    @StateObject var cameraService = CameraService()

    // ── UI state ──────────────────────────────────────────────────────────────
    @State var cameraState: UnifiedCameraState = .scanning
    @State var scannedRawValue: String?
    @State var capturedImage: UIImage?
    @State var showManualEntryPopup: Bool = false
    @State var scannedBottleContainerStatus: StockCountOptionContainerStatus = .sealed

    // ── Pill count panel ──────────────────────────────────────────────────────
    @State var showPillCountPanel: Bool

    init(currentScanType: ScanType) {
        self.currentScanType = currentScanType
        self._showPillCountPanel = State(initialValue: currentScanType == .resumeCount)
    }
    @State var hasInitializedStep: Bool = false
    @State var isAddDisabled: Bool = false
    @State var showSuccessAnimation: Bool = false
    @State var lastAddedCount: Int = 0

    @State var showNoteOption: Bool = false
    @State var showConfirmCompletionPopup: Bool = false
    @State var showDeleteAllTransactionDetailsPopup: Bool = false
    @State var showStepCompletionPopup: Bool = false
    @State var showCountMismatchPopup: Bool = false
    @State var selectedTransactionDetail: PillCountTransactionDetailsEntity?
    @State var showTransactionHistory: Bool = true
    @State var isPaused: Bool = false
    @State var errorMessageOfNote: String?
    @State var addNoteSettings: Bool = AppStorageManager.shared.isPillCountingEnabled
    @State var showDetailGrid: Bool = false

    @State var scanTimeoutTask: Task<Void, Never>?
    let scanTimeoutSeconds: UInt64 = 6

    @StateObject private var locationService = LocationService.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLandscape) var isLandscape

    var body: some View {
        rootWithAllPopups
    }

    // MARK: - Layout composition

    private var rootWithAllPopups: some View {
        rootWithPillCountSheet
            .fullScreenCover(isPresented: $showDetailGrid, onDismiss: {
                cameraService.resumeCounting()
            }) {
                PillScanDetailGridScreen()
                    .environmentObject(appColors)
                    .environmentObject(router)
                    .environmentObject(pillScanViewModel)
            }
            .onChange(of: showDetailGrid) { _, isShowing in
                if isShowing { cameraService.pauseCounting() }
            }
            .customPopup(isPresented: $showNoteOption) { showNoteOptionPopup }
            .customPopup(isPresented: $showConfirmCompletionPopup) { showConfirmCompletion }
            .customPopup(isPresented: $showDeleteAllTransactionDetailsPopup) { deleteAllTransactionDetailsPopup }
            .customPopup(isPresented: $showStepCompletionPopup) { showStepCompletion }
            .customPopup(isPresented: $showCountMismatchPopup) { countMismatchDialog }
            .overlay {
                if showSuccessAnimation {
                    SuccessAnimationView(count: lastAddedCount, color: appColors.secondary)
                        .allowsHitTesting(false)
                }
            }
    }

    var pillCountSheetHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad
            ? UIScreen.main.bounds.height * 0.30
            : UIScreen.main.bounds.height * 0.28
    }

    private var rootWithPillCountSheet: some View {
        rootWithBarcodePopups
            .bottomSheet(
                isPresented: $showPillCountPanel,
                dismissOnBackgroundTap: false,
                showDim: false,
                portraitHeight: pillCountSheetHeight,
                landscapeWidth: UIDevice.current.userInterfaceIdiom == .pad ? nil : 280
            ) {
                ZStack {
                    appColors.secondaryBackground.opacity(0.6)
                    if pillScanViewModel.currentControlledStep == .vial {
                        vialControlBottomView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        controlsContent
                    }
                }
            }
    }

    private var rootWithBarcodePopups: some View {
        rootContent
            .bottomSheet(
                isPresented: $pillScanViewModel.showRxFlowPopup,
                onDismiss: {
                    pillScanViewModel.showRxFlowPopup = false
                    restartFlow()
                }
            ) {
                RxDetailsSheetContent(
                    onCancel: {
                        pillScanViewModel.showRxFlowPopup = false
                        restartFlow()
                    },
                    onProceed: {
                        Task {
                            await pillScanViewModel.createTransactionFromRxScan()
                            scanType = .barcode
                            restartFlow()
                        }
                    },
                    drugName: pillScanViewModel.scannedRxData?.drugName ?? "-",
                    quantity: pillScanViewModel.scannedRxData?.qty ?? "-",
                    ndcNumber: pillScanViewModel.scannedRxData?.ndcNo ?? "-",
                    bucket: pillScanViewModel.selectedBucket,
                    rxNumber: pillScanViewModel.scannedRxData?.rxNo ?? "-"
                )
                .environmentObject(appColors)
            }
            .customPopup(isPresented: $pillScanViewModel.showNdcEquivalencePopup, dismissOnBackgroundTap: false) { ndcEquivalencePopup }
            .customPopup(isPresented: $stockCountViewModel.barcodeNotFound) { barcodeNotFoundPopup }
            .customPopup(isPresented: $stockCountViewModel.showStockCountScannedDetails, dismissOnBackgroundTap: false) { stockCountDetailsPopup }
            .customPopup(isPresented: $stockCountViewModel.showScannedNdcDoesNotMatch, dismissOnBackgroundTap: false) { ndcMismatchPopup }
    }

    private var rootContent: some View {
        UnifiedCameraLayout(
            cameraService: cameraService,
            showPillCountPanel: showPillCountPanel,
            pillCountSheetHeight: pillCountSheetHeight,
            isLandscape: isLandscape,
            controlledStepInstruction: controlledStepInstruction,
            onBack: { router.navigateBack() },
            onResume: {
                cameraService.resumeIfPaused()
                cameraService.resetInactivityTimer()
            }
        )
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                cameraService.start()
                cameraService.cancelInactivityTimer()
                if !showPillCountPanel { cameraService.enableBarcodeScanning() }
            case .background, .inactive:
                cameraService.disableBarcodeScanning()
                cameraService.stop()
            @unknown default:
                break
            }
        }
        .onChange(of: cameraService.scannedCode) { _, newValue in handleScannedCode(newValue) }
        .onChange(of: pillScanViewModel.isDrugFound) { _, newValue in handleDrugFoundState(newValue) }
        .onChange(of: pillScanViewModel.isNdcAdded) { _, _ in
            router.setRoot(to: .authentication(.login(.dashboard(.pillCount(.stockCount(.stockCountBatchDetail))))))
        }
        .onChange(of: pillScanViewModel.showCompletionPopup) { _, show in
            if show { showConfirmCompletionPopup = true }
        }
        .onChange(of: pillScanViewModel.rxScanFailed) { _, failed in
            if failed {
                pillScanViewModel.rxScanFailed = false
                restartFlow()
            }
        }
        .onChange(of: pillScanViewModel.currentControlledStep) { _, newStep in
            if showPillCountPanel {
                if hasInitializedStep || currentScanType != .resumeCount {
                    SpeechManager.shared.speak(newStep.displayText)
                }
                hasInitializedStep = true
                pillScanViewModel.getAllTransactionDetailsOfTheCurrentTransaction()
            }
            if newStep == .vial {
                cameraService.pauseCounting()
            } else {
                cameraService.resumeCounting()
            }
        }
        .onChange(of: scanType) { _, newType in
            if newType != .resumeCount { handleStepVoice() }
        }
        .onChange(of: pillScanViewModel.showScannedDrugInfoPopoup) { _, isShowing in
            if isShowing && scanType == .barcode {
                pillScanViewModel.showToastMessage(text: L10n.BarcodeScan.qrScannedSuccessfully)
                handleSubstitute()
            }
        }
        .onChange(of: pillScanViewModel.ndcMismatchRestartFlow) { _, triggered in
            if triggered && currentScanType != .resumeCount {
                pillScanViewModel.ndcMismatchRestartFlow = false
                restartFlow()
            }
        }
        .onChange(of: pillScanViewModel.vialDoneTriggered) { _, triggered in
            if triggered {
                pillScanViewModel.vialDoneTriggered = false
                handleVialDone()
            }
        }
    }

    // MARK: - Computed helpers

    var controlledStepInstruction: String {
        let raw = pillScanViewModel.currentTransaction?.count_type ?? ""
        if raw == CountType.REGULAR.rawValue {
            return L10n.Controlled.regularTargetReverification
        }
        return pillScanViewModel.currentControlledStep.displayText
    }

    private var controlsContent: some View {
        BottomControlsView(
            isLandscape: isLandscape,
            pillScanViewModel: pillScanViewModel,
            cameraService: cameraService,
            appColors: appColors,
            isAddButtonDisabled: isAddDisabled,
            onAddPill: { handleAdd() },
            onComplete: { handleComplete() },
            onReset: { showDeleteAllTransactionDetailsPopup = true },
            onShowDetailGrid: { showDetailGrid = true },
            showTransactionDetails: $showTransactionHistory,
            isPaused: $isPaused
        )
    }

    private var vialControlBottomView: some View {
        VialBottomContentView()
            .environmentObject(cameraService)
    }
}

// MARK: - Lifecycle
extension UnifiedCameraView {

    func onAppear() {
        pillScanViewModel.showRxFlowPopup = false
        pillScanViewModel.showNdcEquivalencePopup = false
        pillScanViewModel.showScannedDrugInfoPopoup = false
        stockCountViewModel.showStockCountScannedDetails = false
        stockCountViewModel.barcodeNotFound = false
        stockCountViewModel.showScannedNdcDoesNotMatch = false
        pillScanViewModel.isDrugFound = nil

        stockCountViewModel.reset()
        pillScanViewModel.resetScanningState()
        cameraState = .scanning
        scannedRawValue = nil
        capturedImage = nil
        hasInitializedStep = false
        scanType = currentScanType

        if currentScanType != .resumeCount {
            pillScanViewModel.selectedTransaction = nil
            pillScanViewModel.currentTransaction = nil
            pillScanViewModel.scannedRxData = nil
            pillScanViewModel.selectedBucket = ""
        }

        cameraService.configureInitialOrientation()
        cameraService.startObservingOrientation()

        if currentScanType == .resumeCount {
            if let selected = pillScanViewModel.selectedTransaction {
                pillScanViewModel.currentTransaction = selected
                pillScanViewModel.getControlledStep(pillCountTxn: selected)
                pillScanViewModel.getAllTransactionDetailsOfTheCurrentTransaction()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                cameraService.start()
                cameraService.cancelInactivityTimer()
                initializeTransaction()
                cameraService.resumeCounting()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                cameraService.start()
                cameraService.cancelInactivityTimer()
                cameraService.enableBarcodeScanning()
                startScanTimeout()
            }
        }
    }

    func onDisappear() {
        scanTimeoutTask?.cancel()
        cameraService.disableBarcodeScanning()
        cameraService.stop()
        pillScanViewModel.showRxFlowPopup = false
        pillScanViewModel.showNdcEquivalencePopup = false
        pillScanViewModel.showScannedDrugInfoPopoup = false
        stockCountViewModel.showStockCountScannedDetails = false
        stockCountViewModel.barcodeNotFound = false
        stockCountViewModel.showScannedNdcDoesNotMatch = false
        pillScanViewModel.selectedTransaction = nil
        pillScanViewModel.targetCount = ["", "", "", ""]
        pillScanViewModel.currentTransaction = nil
        pillScanViewModel.currentTransactionTransactionDetails = nil
        pillScanViewModel.note = ""
        pillScanViewModel.currentControlledStep = .scan
        pillScanViewModel.currentControlledTargetCount = nil
        pillScanViewModel.capturedVialImage = nil
        pillScanViewModel.vialCapturedImagePath = nil
        pillScanViewModel.vialDoneTriggered = false
        pillScanViewModel.reset()
    }
}

// MARK: - Event Handlers
extension UnifiedCameraView {

    func handleStepVoice() {
        SpeechManager.shared.speak(scanType.instructionText)
    }


    func handleScannedCode(_ newValue: String) {
        guard !newValue.isEmpty,
//              pillScanViewModel.isDrugFound == nil,
              !pillScanViewModel.isCheckingNdc
        else {
            print("SCANN STOP PPPPP")
            return
        }

        cameraService.disableBarcodeScanning()
        cameraService.pauseCounting()

        if let snap = cameraService.captureSnapshot() { self.capturedImage = snap }
        scannedRawValue = newValue

        Task { @MainActor in
            
//            guard pillScanViewModel.checkIsNdcMatch(rawValueFromBarcodeOrQr: newValue) else { return }

            if router.selectedPillScanningType == .FIXED
//                && pillScanViewModel.selectedTransaction?.target_count == nil
            {
                switch scanType {
                case .rx_label:
                    if pillScanViewModel.matchesBarcodeFormat(newValue) {
                        cameraState = .rxDetected
                        pillScanViewModel.parseScanData(actualValue: newValue)
                    } else {
                        pillScanViewModel.showToastMessage(text: "Invalid RX Barcode")
                        restartFlow()
                    }
                case .barcode:
                    guard pillScanViewModel.checkIsNdcMatch(rawValueFromBarcodeOrQr: newValue) else { return }
                case .stockCount:
                    await stockCountViewModel.getScannedDrugData(rawValue: newValue)
                case .resumeCount:
                    break;
                }
            } else {
                await stockCountViewModel.getScannedDrugData(rawValue: newValue)
            }
        }
    }

    func handleDrugFoundState(_ newValue: Bool?) {
        switch newValue {
        case true:
            pillScanViewModel.isDrugFound = nil
            cameraService.disableBarcodeScanning()
            scanTimeoutTask?.cancel()
            initializeTransaction()
            showPillCountPanel = true
            cameraService.resumeCounting()
        case false:
            showManualEntryPopup = true
        default:
            showManualEntryPopup = false
        }
    }

    func initializeTransaction() {
        Task {
            if pillScanViewModel.currentTransaction == nil {
                let txnId = userViewModel.currentTransactionTxnId ?? 0
                await pillScanViewModel.getCurrentTransaction(txnId: txnId)
            }
            await MainActor.run {
                pillScanViewModel.getControlledStep(pillCountTxn: pillScanViewModel.currentTransaction)
                pillScanViewModel.addCurrentOpenPillCount = 0
            }
        }
    }

    func startScanTimeout() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: scanTimeoutSeconds * 1_000_000_000)
            if cameraService.scannedCode.isEmpty && pillScanViewModel.isDrugFound == nil {
                await MainActor.run { showManualEntryPopup = true }
            }
        }
    }

    func restartFlow() {
        cameraState = .scanning
        scannedRawValue = nil
        capturedImage = nil
        pillScanViewModel.isCheckingNdc = false
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
        cameraService.resumeCounting()
        startScanTimeout()
        pillScanViewModel.ndcComparisonResponse = nil
        pillScanViewModel.isNdcEquivalent = false
        pillScanViewModel.showNdcEquivalencePopup = false
        stockCountViewModel.reset()
    }

    func handleAdd() {
        guard !isAddDisabled else { return }
        cameraService.resetInactivityTimer()
        cameraService.resumeIfPaused()

        guard cameraService.stableCount > 0 else {
            pillScanViewModel.showToastMessage(text: L10n.PillCount.zeroPillsMessage)
            return
        }

        let stepTotal = Int(pillScanViewModel.getTotalCuntForCurrentStep())
        let newTotal = stepTotal + cameraService.stableCount
        let stepTarget = pillScanViewModel.currentControlledTargetCount ?? 0

        if stepTarget > 0 && newTotal > stepTarget {
            pillScanViewModel.showToastMessage(text: L10n.PillCount.totalCountExceedsTarget)
            return
        }

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
            guard let processed = rawImage.compressedGrayscale(maxWidth: 1080, quality: 1.0) else { return }
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
            savedPath = PhotoFileManager.shared.saveImage(finalImage)
        }

        if pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue {
            pillScanViewModel.addCurrentOpenPillCount += cameraService.stableCount
        } else {
            pillScanViewModel.addTransactionDetailToCurrentTransaction(
                pillCount: Int32(cameraService.stableCount),
                imagePath: savedPath,
                type: pillScanViewModel.currentControlledStep.rawValue
            )
        }
    }

    func handleComplete() {
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

        if nextStep == nil {
            if pillScanViewModel.currentTransaction?.is_from_pms != true
                && pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
                showNoteOption = true
            } else {
                showConfirmCompletionPopup = true
            }
            return
        }

        showStepCompletionPopup = true
    }

    func handleVialDone() {
        let isPmsTxn = pillScanViewModel.currentTransaction?.is_from_pms ?? false
        let steps = PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction)
        let nextStep = pillScanViewModel.currentControlledStep.next(orderedSteps: steps)
        if addNoteSettings && !isPmsTxn {
            showNoteOption = true
        } else if nextStep == nil {
            showConfirmCompletionPopup = true
        } else {
            showStepCompletionPopup = true
        }
    }

    func handleStockCountAdd() {
        Task {
            guard let batchId = stockCountViewModel.currentBatch?.batch_id else { return }
            await pillScanViewModel.createTxnForBatchFromScan(
                rawValueFromBarcodeOrQr: scannedRawValue,
                ndc: stockCountViewModel.scannedDrugData?.ndc ?? "",
                drugName: stockCountViewModel.scannedDrugData?.drugName ?? "",
                quantity: Int32(Int(stockCountViewModel.scannedDrugData?.quantity ?? 0)),
                countType: .REGULAR,
                batchId: batchId,
                containerStatus: scannedBottleContainerStatus
            )
            stockCountViewModel.showStockCountScannedDetails = false
        }
    }

    func handleSubstitute() {
//        let value = (scannedRawValue?.isEmpty ?? true) ? pillScanViewModel.ndcNumber : scannedRawValue!
        let value = (scannedRawValue?.isEmpty ?? true) ? scannedRawValue! : scannedRawValue!
        Task { @MainActor in
            guard let txnId = pillScanViewModel.selectedTransaction?.txn_id else { return }
            await pillScanViewModel.updateSubstitutedDrug(
                txnId: txnId,
                rawValue: value,
                countType: router.selectedPillScanningType ?? .FIXED,
                image: capturedImage
            )
            pillScanViewModel.markNdcVerified()
            pillScanViewModel.showNdcEquivalencePopup = false
        }
    }
}
