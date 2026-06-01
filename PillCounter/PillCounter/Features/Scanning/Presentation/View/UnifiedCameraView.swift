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

    // ── Stock count panel (always visible when scanType == .stockCount) ───────
    @State var showStockCountPanel: Bool
    @State private var stockSheetCurrentHeight: CGFloat = UIScreen.main.bounds.height * 0.48
    @State private var stockSheetCurrentWidth: CGFloat = UIScreen.main.bounds.width * 0.60
    @State private var stockSheetIsExpanded: Bool = false

    init(currentScanType: ScanType) {
        self.currentScanType = currentScanType
        self._showPillCountPanel = State(initialValue: currentScanType == .resumeCount)
        self._showStockCountPanel = State(initialValue: currentScanType == .stockCount)
    }
    @State var hasInitializedStep: Bool = false
    @State var isAddDisabled: Bool = false
    @State var showSuccessAnimation: Bool = false
    @State var lastAddedCount: Int = 0

    // Open pill scan mode — true while the user is counting loose pills from the stock count sheet
    @State var isOpenPillScanMode: Bool = false
    @State var openPillScanNdc: String = ""

    @State var showNoteOption: Bool = false
    @State var showConfirmCompletionPopup: Bool = false
    // Stock count end-count popups
    @State var showStockEndBatchPopUp: Bool = false
    @State var showStockNoteOptions:   Bool = false
    @State var stockNoteError: String?
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

    /// After a rejection (API fail / no match), the same barcode is ignored
    /// until this date passes. Prevents continuous flickering while the user
    /// hasn't moved the camera, but still allows a retry after the cooldown.
    @State private var rejectedBarcodes: [String: Date] = [:]
    let barcodeCooldownSeconds: TimeInterval = 4

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
            .customPopup(isPresented: $showStockEndBatchPopUp) { stockEndBatchPopup }
            .customPopup(isPresented: $showStockNoteOptions)   { stockNoteOptionPopup }
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

    var stockCountSheetHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad
            ? UIScreen.main.bounds.height * 0.45
            : UIScreen.main.bounds.height * 0.48
    }

    var stockCountSheetExpandedHeight: CGFloat {
        UIScreen.main.bounds.height * 0.90
    }

    var stockCountSheetExpandedWidth: CGFloat {
        UIScreen.main.bounds.width * 0.90
    }

    func snapStockSheet(portrait height: CGFloat) {
        let mid = (stockCountSheetExpandedHeight + stockCountSheetHeight) / 2
        let target = height > mid ? stockCountSheetExpandedHeight : stockCountSheetHeight
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            stockSheetCurrentHeight = target
            stockSheetIsExpanded = (target == stockCountSheetExpandedHeight)
        }
    }

    func snapStockSheet(landscape width: CGFloat) {
        let mid = (stockCountSheetExpandedWidth + stockCountSheetWidth) / 2
        let target = width > mid ? stockCountSheetExpandedWidth : stockCountSheetWidth
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            stockSheetCurrentWidth = target
            stockSheetIsExpanded = (target == stockCountSheetExpandedWidth)
        }
    }

    var stockCountSheetWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad
            ? UIScreen.main.bounds.width * 0.40
            : UIScreen.main.bounds.width * 0.60
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
            .bottomSheet(
                isPresented: $showStockCountPanel,
                dismissOnBackgroundTap: false,
                showDim: false,
                portraitHeight: stockCountSheetHeight,
                landscapeWidth: stockCountSheetWidth,
                heightBinding: UIDevice.current.userInterfaceIdiom == .pad ? nil : $stockSheetCurrentHeight,
                widthBinding: UIDevice.current.userInterfaceIdiom == .pad ? nil : $stockSheetCurrentWidth
            ) {
                StockCountBatchBottomSheet(
                    containerStatus: $scannedBottleContainerStatus,
                    isExpanded: $stockSheetIsExpanded,
                    onPortraitDragChanged: { translationY in
                        let base = stockSheetIsExpanded ? stockCountSheetExpandedHeight : stockCountSheetHeight
                        let clamped = min(max(base - translationY, stockCountSheetHeight), stockCountSheetExpandedHeight + 20)
                        stockSheetCurrentHeight = clamped
                    },
                    onPortraitDragEnded: { snapStockSheet(portrait: stockSheetCurrentHeight) },
                    onLandscapeDragChanged: { translationX in
                        // Drag left = negative translationX = expanding (sheet comes from right)
                        let base = stockSheetIsExpanded ? stockCountSheetExpandedWidth : stockCountSheetWidth
                        let clamped = min(max(base - translationX, stockCountSheetWidth), stockCountSheetExpandedWidth + 20)
                        stockSheetCurrentWidth = clamped
                    },
                    onLandscapeDragEnded: { snapStockSheet(landscape: stockSheetCurrentWidth) },
                    onCancel: { dismissScannedDetails() },
                    onAdd: { dismissScannedDetails() },
                    onEndCount: { handleStockEndCount() },
                    onScanPills: { handleOpenPillScanRequest() }
                )
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
            }
            .customPopup(isPresented: $stockCountViewModel.showScannedNdcDoesNotMatch, dismissOnBackgroundTap: false) { ndcMismatchPopup }
    }

    private var rootContent: some View {
        UnifiedCameraLayout(
            cameraService: cameraService,
            showPillCountPanel: showPillCountPanel,
            pillCountSheetHeight: pillCountSheetHeight,
            isLandscape: isLandscape,
            controlledStepInstruction: controlledStepInstruction,
            showPillDetectionUI: currentScanType != .stockCount || isOpenPillScanMode,
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
                if currentScanType == .stockCount && !isOpenPillScanMode {
                    cameraService.pauseCounting()
                }
            case .background, .inactive:
                cameraService.disableBarcodeScanning()
                cameraService.stop()
            @unknown default:
                break
            }
        }
        .onChange(of: cameraService.scannedCode) { _, newValue in handleScannedCode(newValue) }
        .onChange(of: pillScanViewModel.isDrugFound) { _, newValue in handleDrugFoundState(newValue) }
        .onChange(of: pillScanViewModel.isNdcAdded) { _, added in
            if added && currentScanType == .stockCount {
                // Stock count: only clear the flag; reset() is called explicitly by autoCommitPendingStockScan
                // before fetching new drug data. Calling it here would wipe scannedDrugData mid-fetch.
                pillScanViewModel.isNdcAdded = false
            } else if added {
                router.setRoot(to: .authentication(.login(.dashboard(.pillCount(.stockCount(.stockCountBatchDetail))))))
            }
        }
        .onChange(of: pillScanViewModel.showCompletionPopup) { _, show in
            if show { showConfirmCompletionPopup = true }
        }
        .onChange(of: pillScanViewModel.rxScanFailed) { _, failed in
            if failed {
                pillScanViewModel.rxScanFailed = false
                if let barcode = scannedRawValue { markBarcodeRejected(barcode) }
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
            guard currentScanType != .stockCount else { return }
            if newStep == .vial {
                cameraService.pauseCounting()
            } else {
                cameraService.resumeCounting()
            }
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
                if let barcode = scannedRawValue { markBarcodeRejected(barcode) }
                restartFlow()
            }
        }
        .onChange(of: pillScanViewModel.vialDoneTriggered) { _, triggered in
            if triggered {
                pillScanViewModel.vialDoneTriggered = false
                handleVialDone()
            }
        }
        .onChange(of: showStockCountPanel) { _, visible in
            if !visible {
                stockSheetCurrentHeight = stockCountSheetHeight
                stockSheetCurrentWidth = stockCountSheetWidth
                stockSheetIsExpanded = false
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
        showStockCountPanel = currentScanType == .stockCount
        stockSheetCurrentHeight = stockCountSheetHeight
        stockSheetCurrentWidth = stockCountSheetWidth
        stockSheetIsExpanded = false
        pillScanViewModel.resetScanningState()
        cameraState = .scanning
        scannedRawValue = nil
        capturedImage = nil
        hasInitializedStep = false
        scanType = currentScanType

        // Only clear transaction state for a truly fresh scan.
        // When resuming with .barcode (NDC not yet verified), selectedTransaction
        // is already set by the caller and must be preserved for NDC matching.
        let isResumingWithBarcode = currentScanType == .barcode
            && pillScanViewModel.selectedTransaction != nil
            && userViewModel.currentTransactionTxnId != nil

        if currentScanType != .resumeCount && !isResumingWithBarcode {
            pillScanViewModel.selectedTransaction = nil
            pillScanViewModel.currentTransaction = nil
            pillScanViewModel.scannedRxData = nil
            pillScanViewModel.selectedBucket = ""
        }

        cameraService.configureInitialOrientation()
        cameraService.startObservingOrientation()

        speakOnAppear()

        if currentScanType == .resumeCount {
            if let selected = pillScanViewModel.selectedTransaction {
                pillScanViewModel.currentTransaction = selected
                pillScanViewModel.getControlledStep(pillCountTxn: selected)
                pillScanViewModel.getAllTransactionDetailsOfTheCurrentTransaction()
            }
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                cameraService.start()
                cameraService.cancelInactivityTimer()
                initializeTransaction()
                if pillScanViewModel.currentControlledStep != .vial {
                    cameraService.resumeCounting()
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                cameraService.start()
                cameraService.cancelInactivityTimer()
                cameraService.enableBarcodeScanning()
                if currentScanType == .stockCount {
                    // Stock count only needs barcode scanning; pill detection must stay off.
                    cameraService.pauseCounting()
                } else {
                    startScanTimeout()
                }
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

    func speakOnAppear() {
        switch currentScanType {
        case .resumeCount:
            SpeechManager.shared.speak(pillScanViewModel.currentControlledStep.displayText)
        default:
            SpeechManager.shared.speak(currentScanType.instructionText)
        }
    }


    func markBarcodeRejected(_ barcode: String) {
        rejectedBarcodes[barcode] = Date().addingTimeInterval(barcodeCooldownSeconds)
    }

    func handleScannedCode(_ newValue: String) {
        guard !newValue.isEmpty,
//              pillScanViewModel.isDrugFound == nil,
              !pillScanViewModel.isCheckingNdc
        else {
            print("SCANN STOP PPPPP")
            return
        }

        // If this barcode was recently rejected, silently skip it until the cooldown expires.
        if let retryAfter = rejectedBarcodes[newValue], Date() < retryAfter {
            cameraService.resetBarcodeScanState()
            cameraService.enableBarcodeScanning()
            return
        }
        rejectedBarcodes.removeValue(forKey: newValue)

        cameraService.disableBarcodeScanning()
        if currentScanType != .stockCount { cameraService.pauseCounting() }

        if let snap = cameraService.captureSnapshot() { self.capturedImage = snap }
        scannedRawValue = newValue

        Task { @MainActor in
            

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
                    await handleStockCountScan(newValue)
                case .resumeCount:
                    break
                }
            } else {
                await handleStockCountScan(newValue)
            }
        }
    }

    func handleDrugFoundState(_ newValue: Bool?) {
        switch newValue {
        case true:
            pillScanViewModel.isDrugFound = nil
            if currentScanType == .stockCount && !isOpenPillScanMode {
                // Sealed stock count ADD: transaction created, scanning re-enabled
                stockCountViewModel.reset()
                return
            }
            if isOpenPillScanMode {
                // Open pill barcode matched — start pill counting
                cameraService.disableBarcodeScanning()
                showPillCountPanel = true
                initializeTransaction()
                return
            }
            cameraService.disableBarcodeScanning()
            scanTimeoutTask?.cancel()
            showPillCountPanel = true
            initializeTransaction()
        case false:
            showManualEntryPopup = true
        default:
            showManualEntryPopup = false
        }
    }

    func initializeTransaction() {
        guard currentScanType != .stockCount || isOpenPillScanMode else { return }
        Task {
            if pillScanViewModel.currentTransaction == nil {
                let txnId = userViewModel.currentTransactionTxnId ?? 0
                await pillScanViewModel.getCurrentTransaction(txnId: txnId)
            }
            await MainActor.run {
                pillScanViewModel.getControlledStep(pillCountTxn: pillScanViewModel.currentTransaction)
                pillScanViewModel.addCurrentOpenPillCount = 0
                if pillScanViewModel.currentControlledStep == .vial {
                    cameraService.pauseCounting()
                } else {
                    cameraService.resumeCounting()
                }
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
        // Prune expired entries so the dict doesn't grow unbounded.
        let now = Date()
        rejectedBarcodes = rejectedBarcodes.filter { $0.value > now }
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
        if currentScanType != .stockCount { cameraService.resumeCounting() }
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

        pillScanViewModel.addTransactionDetailToCurrentTransaction(
            pillCount: Int32(cameraService.stableCount),
            imagePath: savedPath,
            type: pillScanViewModel.currentControlledStep.rawValue
        )
        if isOpenPillScanMode {
            pillScanViewModel.addCurrentOpenPillCount += cameraService.stableCount
        }
    }

    func handleComplete() {
        if isOpenPillScanMode {
            handleOpenPillCountComplete()
            return
        }

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
        Task { await performStockCountAdd() }
    }

    /// Auto-called after a scan, and also by the manual Add button.
    /// Suppresses list reload while writing so the list doesn't update mid-session.
    /// List refreshes only when the user taps Add/Clear (dismissScannedDetails).
    func performStockCountAdd() async {
        guard let batchId = stockCountViewModel.currentBatch?.batch_id,
              let drug = stockCountViewModel.scannedDrugData else { return }
        stockCountViewModel.suppressListReload = true
        if pillScanViewModel.selectedTransaction?.is_from_pms == true,
           let txn = pillScanViewModel.selectedTransaction {
            pillScanViewModel.updatePmsTxnCount(
                txn: txn,
                containerStatus: scannedBottleContainerStatus,
                scannedQty: Int(drug.quantity)
            )
            stockCountViewModel.committedTxnId = txn.txn_id
        } else {
            await pillScanViewModel.createTxnForBatchFromScan(
                rawValueFromBarcodeOrQr: drug.rawBarcode,
                ndc: drug.ndc,
                drugName: drug.drugName,
                quantity: Int32(drug.quantity),
                countType: .REGULAR,
                batchId: batchId,
                containerStatus: scannedBottleContainerStatus,
                bottleCount: stockCountViewModel.pendingBottleCount
            )
            stockCountViewModel.committedTxnId = pillScanViewModel.currentTransaction?.txn_id
        }
        // Keep scannedDrugData alive so the details slot stays visible.
        stockCountViewModel.showStockCountScannedDetails = true
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
    }

    /// Called by Add/Clear buttons — dismisses the details panel and refreshes the list.
    func dismissScannedDetails() {
        stockCountViewModel.suppressListReload = false
        stockCountViewModel.reset()
        stockCountViewModel.reloadAllState()
    }

    /// Handles a new barcode in stock-count flow:
    /// - Same barcode as current pending drug → increment bottle count, apply 5s cooldown, no UI flicker
    /// - Different barcode → auto-commit pending drug first, then show new drug info
    func handleStockCountScan(_ rawValue: String) async {
        // In open pill mode the barcode is used to identify which NDC is being counted.
        // Create/update the transaction with .opened status, then start pill counting.
        if isOpenPillScanMode {
            await handleOpenPillBarcodeScan(rawValue)
            return
        }

        // Lazily create the batch on the very first scan instead of on bucket selection.
        stockCountViewModel.ensureBatchExists()

        // Decode to extract GTIN for same-drug detection
        let decoded = stockCountViewModel.decoder.decode(rawValue)
        let scannedGtin = decoded.gtin ?? ""

        // Check if this is the same drug already showing
        let isSameNdc: Bool = {
            guard let drug = stockCountViewModel.scannedDrugData, !drug.ndc.isEmpty else { return false }
            if !scannedGtin.isEmpty {
                return drug.gtin == scannedGtin
            }
            // Fallback: compare raw value directly against known NDC
            return drug.ndc == rawValue
        }()

        if isSameNdc {
            // Same barcode held in front — increment sealed bottle count, commit immediately,
            // and apply a cooldown so it doesn't keep firing while the label stays in frame.
            stockCountViewModel.pendingBottleCount += 1
            await performStockCountAdd()
            rejectedBarcodes[rawValue] = Date().addingTimeInterval(3)
        } else {
            // Different NDC — commit any pending drug first, then fetch and auto-add the new one.
            await autoCommitPendingStockScan()
            await stockCountViewModel.getScannedDrugData(rawValue: rawValue)
            // Auto-add the scanned drug without requiring a manual tap.
            if stockCountViewModel.scannedDrugData != nil {
                await performStockCountAdd()
            }
            // Apply a short cooldown on the new barcode too so the just-scanned label
            // doesn't immediately re-trigger before the user moves the camera away.
            rejectedBarcodes[rawValue] = Date().addingTimeInterval(3)
        }

        // Always re-enable scanning so any barcode (including a new one) can be read.
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
    }

    /// In open pill mode: scan the barcode to confirm/find the drug, then increment open_bottle_qty
    /// and hand off to pill counting. If the scanned NDC doesn't match the expected one, show an error.
    func handleOpenPillBarcodeScan(_ rawValue: String) async {
        stockCountViewModel.ensureBatchExists()
        guard let batchId = stockCountViewModel.currentBatch?.batch_id else { return }

        await stockCountViewModel.getScannedDrugData(rawValue: rawValue)

        guard let drug = stockCountViewModel.scannedDrugData else {
            cameraService.resetBarcodeScanState()
            cameraService.enableBarcodeScanning()
            return
        }

        // Warn if the scanned bottle is a different NDC than the one selected for open pill scan.
        if !openPillScanNdc.isEmpty && drug.ndc != openPillScanNdc {
            stockCountViewModel.showScannedNdcDoesNotMatch = true
            cameraService.resetBarcodeScanState()
            cameraService.enableBarcodeScanning()
            return
        }

        openPillScanNdc = drug.ndc
        scannedBottleContainerStatus = .opened

        await pillScanViewModel.createTxnForBatchFromScan(
            rawValueFromBarcodeOrQr: rawValue,
            ndc: drug.ndc,
            drugName: drug.drugName,
            quantity: drug.quantity,
            countType: .REGULAR,
            batchId: batchId,
            containerStatus: .opened
        )

        rejectedBarcodes[rawValue] = Date().addingTimeInterval(3)
        // isDrugFound = true fires from handlePostScanUI → handleDrugFoundState starts pill counting
    }

    /// Called when a new barcode is scanned while a drug's details are showing.
    /// Treats the current details as "Add tapped" — refreshes list then clears for next scan.
    func autoCommitPendingStockScan() async {
        guard stockCountViewModel.scannedDrugData != nil else { return }
        if stockCountViewModel.committedTxnId != nil {
            // Already auto-added — flush suppression and reload list (same as tapping Add).
            stockCountViewModel.suppressListReload = false
            stockCountViewModel.reloadAllState()
            stockCountViewModel.reset()
            return
        }
        // Drug was fetched but never committed — commit silently first.
        guard let drug = stockCountViewModel.scannedDrugData,
              let batchId = stockCountViewModel.currentBatch?.batch_id else { return }
        stockCountViewModel.suppressListReload = true
        await pillScanViewModel.createTxnForBatchFromScan(
            rawValueFromBarcodeOrQr: drug.rawBarcode,
            ndc: drug.ndc,
            drugName: drug.drugName,
            quantity: Int32(drug.quantity),
            countType: .REGULAR,
            batchId: batchId,
            containerStatus: scannedBottleContainerStatus,
            bottleCount: stockCountViewModel.pendingBottleCount
        )
        stockCountViewModel.suppressListReload = false
        stockCountViewModel.reloadAllState()
        stockCountViewModel.reset()
    }

    // MARK: - Stock count end-count flow

    func handleStockEndCount() {
        if stockCountViewModel.isNoteEnable {
            stockCountViewModel.note = ""
            showStockNoteOptions = true
        } else {
            showStockEndBatchPopUp = true
        }
    }

    // MARK: - Open Pill Scan

    func handleOpenPillScanRequest() {
        // Pre-fill NDC if a drug is already selected; otherwise leave empty so the
        // barcode scan (handleOpenPillBarcodeScan) will set it after the user scans.
        let ndc = stockCountViewModel.scannedDrugData?.ndc
            ?? stockCountViewModel.selectedGroupedTransaction?.ndc
            ?? ""
        openPillScanNdc = ndc
        isOpenPillScanMode = true
        showStockCountPanel = false
        stockCountViewModel.reset()
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
        // Do NOT show the pill count panel here — it opens after the barcode is
        // scanned and handleDrugFoundState receives isDrugFound == true.
    }

    func handleOpenPillCountComplete() {
        guard isOpenPillScanMode,
              let batchId = stockCountViewModel.currentBatch?.batch_id else { return }
        let loosePills = pillScanViewModel.addCurrentOpenPillCount
        pillScanViewModel.updateOpenPillCount(ndc: openPillScanNdc, batchId: batchId, loosePillCount: loosePills)

        // Reset all pill-scan state so the next stock-count barcode scan starts clean.
        pillScanViewModel.addCurrentOpenPillCount = 0
        pillScanViewModel.currentTransaction = nil
        pillScanViewModel.selectedTransaction = nil
        pillScanViewModel.currentTransactionTransactionDetails = nil
        pillScanViewModel.currentControlledStep = .scan
        pillScanViewModel.isCheckingNdc = false
        pillScanViewModel.isDrugFound = nil

        isOpenPillScanMode = false
        openPillScanNdc = ""
        scannedRawValue = nil
        scannedBottleContainerStatus = .sealed
        showPillCountPanel = false

        // Flush any suppression left from the open-pill add, then reload list.
        stockCountViewModel.suppressListReload = false
        stockCountViewModel.reset()
        stockCountViewModel.reloadAllState()

        cameraService.pauseCounting()
        cameraService.start()
        cameraService.cancelInactivityTimer()
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
        showStockCountPanel = true
    }

    private func confirmStockEndBatch() {
        showStockEndBatchPopUp = false
        if let batchId = stockCountViewModel.currentBatch?.batch_id {
            stockCountViewModel.completeBatch(batchId: batchId)
        }
        stockCountViewModel.note = ""
        router.setRoot(to: .authentication(.login(.dashboard(.dashboardHome))))
    }

    var stockHasNoCount: Bool {
        stockCountViewModel.groupedTransactions.isEmpty ||
        stockCountViewModel.groupedTransactions.reduce(0) { $0 + Int($1.total) } == 0
    }

    var stockEndBatchPopup: some View {
        ConfirmationDialogue(
            title: "End Batch Count?",
            message: stockHasNoCount ? "No items have been counted. Are you sure you want to end?" : nil,
            cancelButtonText: "No",
            confirmButtonText: "Yes",
            onCancel: { showStockEndBatchPopUp = false },
            onConfirm: { confirmStockEndBatch() }
        )
    }

    var stockNoteOptionPopup: some View {
        NotePopupView(
            title: "Add a note before ending?",
            text: $stockCountViewModel.note,
            errorMessage: stockNoteError,
            primaryTitle: "Yes",
            primaryAction: {
                if stockCountViewModel.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stockNoteError = "Please add a note"
                    return
                }
                stockNoteError = nil
                showStockNoteOptions = false
                showStockEndBatchPopUp = true
            },
            secondaryTitle: "Skip",
            secondaryAction: {
                stockNoteError = nil
                showStockNoteOptions = false
                stockCountViewModel.note = ""
                showStockEndBatchPopUp = true
            },
            onClose: {
                stockNoteError = nil
                showStockNoteOptions = false
                stockCountViewModel.note = ""
            }
        )
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
