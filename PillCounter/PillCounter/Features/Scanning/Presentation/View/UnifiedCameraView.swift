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
    @State var scanType: ScanType

    @StateObject var cameraService = CameraService()
    @StateObject private var darkAppColors = AppColors.shared.forcedDark()

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
    @State private var stockSheetCurrentWidth: CGFloat = UIScreen.main.bounds.width * 0.45
    @State private var stockSheetIsExpanded: Bool = false

    init(currentScanType: ScanType) {
        self.currentScanType = currentScanType
        self._scanType = State(initialValue: currentScanType)
        self._showPillCountPanel = State(initialValue: currentScanType == .resumeCount)
        self._showStockCountPanel = State(initialValue: currentScanType == .stockCount)
    }
    @State var hasInitializedStep: Bool = false
    @State private var lastSpokenInstruction: String = ""
    @State var isAddDisabled: Bool = false
    @State var showSuccessAnimation: Bool = false
    @State var lastAddedCount: Int = 0

    // Open pill scan mode — true while the user is counting loose pills from the stock count sheet
    @State var isOpenPillScanMode: Bool = false
    @State var openPillScanNdc: String = ""

    @State var showNoteOption: Bool = false
    @State var showConfirmCompletionPopup: Bool = false
    /// "Today's Queue" dispense list shown after a FIXED dispense count is confirmed complete.
    @State var showDispenseQueueSheet: Bool = false
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
    
    // ── Bluetooth HID scanner ─────────────────────────────────────────────────
    @State private var btScannerFocusTrigger: Int = 0

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
//            .customPopup(isPresented: $showStepCompletionPopup) { showStepCompletion }
            .customPopup(isPresented: $showCountMismatchPopup) { countMismatchDialog }
            .customPopup(isPresented: $pillScanViewModel.showHazardousTrayPopup) { hazardousTrayPopup }
            .customPopup(isPresented: $pillScanViewModel.showHazardousTraySubstitutePopup) { hazardousTraySubstitutePopup }
            .bottomSheet(
                isPresented: $showDispenseQueueSheet,
                dismissOnBackgroundTap: false,
                showDim: false,
                portraitHeight: UIScreen.main.bounds.height * 0.50,
                landscapeWidth: UIDevice.current.userInterfaceIdiom == .pad ? 460 : 420
            ) {
                DispenseTransactionListSheetContent(
                    // Continuous dispense — resume the picked txn in place, no navigation.
                    onSelect: { txn in
                        resumeSelectedTransactionInline(txn)
                    }
                )
                .environmentObject(appColors)
                .environmentObject(router)
                .environmentObject(userViewModel)
                .environmentObject(pillScanViewModel)
            }
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
        UIScreen.main.bounds.width
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
            : UIScreen.main.bounds.width * 0.50
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
                    darkAppColors.secondaryBackground.opacity(0.6)
                    if pillScanViewModel.currentControlledStep == .vial {
                        vialControlBottomView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        controlsContent
                    }
                }
                .environmentObject(darkAppColors)
            }
    }

    private var rootWithBarcodePopups: some View {
        rootContent
            .bottomSheet(
                isPresented: $pillScanViewModel.showRxFlowPopup,
                onDismiss: {
                    pillScanViewModel.showRxFlowPopup = false
                    pillScanViewModel.fetchedRxTransaction = nil
                    restartFlow()
                }
            ) {
                RxDetailsSheetContent(
                    onCancel: {
                        pillScanViewModel.showRxFlowPopup = false
                        pillScanViewModel.fetchedRxTransaction = nil
                        restartFlow()
                    },
                    onProceed: {
                        pillScanViewModel.proceedFromRxScan()
                        userViewModel.currentTransactionTxnId = pillScanViewModel.selectedTransaction?.txn_id
                        scanType = .barcode
                        restartFlow()
                    },
                    drugName: pillScanViewModel.fetchedRxTransaction?.drug?.drug_name ?? "-",
                    quantity: pillScanViewModel.fetchedRxTransaction?.target_count.description ?? "-",
                    ndcNumber: pillScanViewModel.fetchedRxTransaction?.drug?.ndc ?? "-",
                    bucket: pillScanViewModel.fetchedRxTransaction?.bucket_id ?? "-",
                    rxNumber: pillScanViewModel.fetchedRxTransaction?.rx_no ?? "-"
                )
                .environmentObject(appColors)
            }
            .bottomSheet(
                isPresented: $pillScanViewModel.showVerifyStockBottlePopup,
                dismissOnBackgroundTap: false,
                onDismiss: {
                    pillScanViewModel.showVerifyStockBottlePopup = false
                }
            ) {
                VerifyStockBottleSheetContent(
                    onCancel: {
                        pillScanViewModel.showVerifyStockBottlePopup = false
                        restartFlow()
                    },
                    onProceed: {
                        pillScanViewModel.showVerifyStockBottlePopup = false
                        // Continue the same-drug flow — the existing onChange observer
                        // on showScannedDrugInfoPopoup runs handleSubstitute() / next step.
                        pillScanViewModel.showScannedDrugInfoPopoup = true
                    },
                    drugName: pillScanViewModel.selectedTransaction?.drug?.drug_name
                        ?? pillScanViewModel.scannedRxData?.drugName ?? "-",
                    ndcNumber: pillScanViewModel.selectedTransaction?.drug?.ndc
                        ?? pillScanViewModel.scannedRxData?.ndcNo ?? "-",
                    bucket: pillScanViewModel.selectedTransaction?.bucket_id
                        ?? (pillScanViewModel.selectedBucket.isEmpty ? "-" : pillScanViewModel.selectedBucket)
                )
                .environmentObject(appColors)
            }
            .customPopup(isPresented: $pillScanViewModel.showNdcEquivalencePopup, dismissOnBackgroundTap: false) { ndcEquivalencePopup }
            .customPopup(isPresented: $pillScanViewModel.showRxOnHoldPopup, dismissOnBackgroundTap: false) { rxOnHoldPopup }
            .onChange(of: stockCountViewModel.barcodeNotFound) { _, notFound in
                if notFound {
                    stockCountViewModel.barcodeNotFound = false
                    pillScanViewModel.showToastMessage(text: L10n.BarcodeScan.drugNotFound)
                    restartFlow()
                }
            }
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
                    onCancel: { clearScannedDetails() },
                    onAdd: { dismissScannedDetails() },
                    onEndCount: { handleStockEndCount() },
                    onScanPills: { handleOpenPillScanRequest() }
                )
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
            }
            .customPopup(isPresented: $stockCountViewModel.showScannedNdcDoesNotMatch, dismissOnBackgroundTap: false) { ndcMismatchPopup }
    }
    
    // Split into two properties so the Swift type-checker doesn't time out
    // on the long onChange chain.
    private var rootContent: some View {
        cameraLayoutWithScanObservers
            .withBtFocusTriggers(
                showPillCountPanel: showPillCountPanel,
                pillScanViewModel: pillScanViewModel,
                stockCountViewModel: stockCountViewModel,
                showManualEntryPopup: showManualEntryPopup,
                btScannerFocusTrigger: $btScannerFocusTrigger
            )
            .overlay(alignment: .topLeading) {
                if !showPillCountPanel {
                    BtScannerInputBar(
                        focusTrigger: $btScannerFocusTrigger,
                        onSubmit: { barcode in
                            guard !barcode.isEmpty else { return }
                            handleScannedCode(barcode)
                        }
                    )
                    .frame(width: 1, height: 1)
                }
            }
    }
    
    private var cameraLayoutWithScanObservers: some View {
        cameraLayoutWithFirstObservers
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
            .onChange(of: showStockCountPanel) { _, visible in
                if !visible {
                    stockSheetCurrentHeight = stockCountSheetHeight
                    stockSheetCurrentWidth = stockCountSheetWidth
                    stockSheetIsExpanded = false
                }
            }
            .onChange(of: cameraService.glovesConfirmed) { _, confirmed in
                if confirmed { pillScanViewModel.updateGlovesDetected(detected: true) }
            }
            .onChange(of: cameraService.detectedTrayColor) { _, color in
                guard let color else { return }
                pillScanViewModel.handleTrayColorDetected(
                    color,
                    drugIsHazardous: pillScanViewModel.currentTransaction?.drug?.is_hazardous == true
                )
            }
            // Tray-colour detection runs ONLY while the pill-count bottom sheet is
            // showing (dispense flow + stock-scan-pills). Off otherwise.
            .onChange(of: showPillCountPanel) { _, showing in
                cameraService.isTrayColorDetectionEnabled = showing
                if showing { pillScanViewModel.resetTrayColorTracking() }
            }
            // Freeze tray-colour detection while either hazardous-tray popup is up so
            // the live feed can't change the captured colour; resume after confirm/dismiss.
            .onChange(of: pillScanViewModel.showHazardousTrayPopup) { _, showingPopup in
                cameraService.isTrayColorDetectionEnabled = showingPopup ? false : showPillCountPanel
            }
            .onChange(of: pillScanViewModel.showHazardousTraySubstitutePopup) { _, showingPopup in
                cameraService.isTrayColorDetectionEnabled = showingPopup ? false : showPillCountPanel
            }
            .onChange(of: pillScanViewModel.currentTransaction) { _, txn in
                cameraService.isGloveDetectionEnabled =
                    (txn?.drug?.is_hazardous == true) && AppStorageManager.shared.isHazardousDrugSetting
            }
    }

    // Split into two properties so the Swift type-checker doesn't time out
    // on the long onChange chain.
    private var cameraLayoutWithFirstObservers: some View {
        UnifiedCameraLayout(
            cameraService: cameraService,
            showPillCountPanel: showPillCountPanel,
            pillCountSheetHeight: pillCountSheetHeight,
            showStockCountPanel: showStockCountPanel || showDispenseQueueSheet,
            stockCountSheetHeight: stockSheetCurrentHeight,
            isLandscape: isLandscape,
            instructionText: overlayInstructionText,
            showPillDetectionUI: currentScanType != .stockCount || isOpenPillScanMode,
            onBack: { router.navigateBack() },
            onResume: {
                cameraService.resumeIfPaused()
                cameraService.resetInactivityTimer()
                // New operator may have taken over — re-verify gloves and clear DB flag.
                cameraService.resetGloveDetection()
                pillScanViewModel.updateGlovesDetected(detected: false)
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
                restartFlow()
            }
        }
        // RX scan succeeded (RX detail popup is about to show) — only now dismiss
        // the continuous-dispense queue sheet. Blocked/failed scans never set this.
        .onChange(of: pillScanViewModel.showRxFlowPopup) { _, showing in
            if showing && showDispenseQueueSheet { showDispenseQueueSheet = false }
        }
        .onChange(of: pillScanViewModel.rxResumeInline) { _, triggered in
            guard triggered else { return }
            pillScanViewModel.rxResumeInline = false
            // RX scan resolved to an inline resume — a success, so close the queue sheet.
            if showDispenseQueueSheet { showDispenseQueueSheet = false }
            guard let txn = pillScanViewModel.currentTransaction else { return }
            pillScanViewModel.getControlledStep(pillCountTxn: txn)
            pillScanViewModel.getAllTransactionDetailsOfTheCurrentTransaction()
            showPillCountPanel = true
            cameraService.disableBarcodeScanning()
            if pillScanViewModel.currentControlledStep != .vial {
                cameraService.resumeCounting()
            }
        }
        .onChange(of: pillScanViewModel.currentControlledStep) { _, newStep in
            if showPillCountPanel {
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
        .onChange(of: unifiedInstructionText) { _, newText in
            speakInstruction(newText)
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

    /// Single source of truth for voice feedback, covering every scan mode.
    var unifiedInstructionText: String {
        if showPillCountPanel {
            // The pill-count panel opens synchronously, but the controlled step is
            // resolved later by initializeTransaction()'s async Task. Until that lands,
            // currentControlledStep is still the placeholder .scan ("Scan Container QR
            // Code"), which gets spoken and then immediately replaced by the real step —
            // two utterances. Suppress the transient placeholder until the step is set.
            if !hasInitializedStep && pillScanViewModel.currentControlledStep == .scan {
                return ""
            }
            return controlledStepInstruction
        }
        if isOpenPillScanMode {
            return L10n.Controlled.scanNdcToCountPills
        }
        return scanType.instructionText
    }

    /// Visual overlay text — same as voice feedback except hidden during stock-count
    /// barcode scan phase (voice-only there; the bottom sheet provides visual context).
    var overlayInstructionText: String {
        if currentScanType == .stockCount && !showPillCountPanel && !isOpenPillScanMode {
            return ""
        }
        return unifiedInstructionText
    }

    private var controlsContent: some View {
        BottomControlsView(
            isLandscape: isLandscape,
            pillScanViewModel: pillScanViewModel,
            cameraService: cameraService,
            appColors: darkAppColors,
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
            .environmentObject(darkAppColors)
    }
}

// MARK: - Lifecycle
extension UnifiedCameraView {

    func onAppear() {
        pillScanViewModel.showRxFlowPopup = false
        pillScanViewModel.showRxOnHoldPopup = false
        pillScanViewModel.showRxInProgressPopup = false
        pillScanViewModel.showNdcEquivalencePopup = false
        pillScanViewModel.showScannedDrugInfoPopoup = false
        pillScanViewModel.showVerifyStockBottlePopup = false
        pillScanViewModel.fetchedRxTransaction = nil
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
        // Seed the tray-colour gate for flows that start with the pill-count sheet
        // already shown (e.g. .resumeCount), since onChange won't fire on appear.
        cameraService.isTrayColorDetectionEnabled = showPillCountPanel
        pillScanViewModel.resetTrayColorTracking()
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
        lastSpokenInstruction = ""
        scanTimeoutTask?.cancel()
        cameraService.disableBarcodeScanning()
        cameraService.isTrayColorDetectionEnabled = false
        cameraService.stop()
        pillScanViewModel.showRxFlowPopup = false
        pillScanViewModel.showRxOnHoldPopup = false
        pillScanViewModel.showRxInProgressPopup = false
        pillScanViewModel.showNdcEquivalencePopup = false
        pillScanViewModel.showScannedDrugInfoPopoup = false
        pillScanViewModel.showVerifyStockBottlePopup = false
        pillScanViewModel.fetchedRxTransaction = nil
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
        pillScanViewModel.rxResumeInline = false
        pillScanViewModel.reset()
    }
}

// MARK: - Event Handlers
extension UnifiedCameraView {

    func speakOnAppear() {
        speakInstruction(unifiedInstructionText)
    }

    private func speakInstruction(_ text: String) {
        guard !text.isEmpty, text != lastSpokenInstruction else { return }
        lastSpokenInstruction = text
        SpeechManager.shared.speak(text)
    }


    func handleScannedCode(_ newValue: String) {
        guard !newValue.isEmpty,
              !pillScanViewModel.isCheckingNdc
        else { return }

        // Continuous dispense note: the queue sheet is NOT dismissed here. It is
        // dismissed only once the RX scan actually succeeds and isn't blocked —
        // see the showRxFlowPopup / rxResumeInline observers below. A failed or
        // blocked scan (not found / on hold) leaves the sheet up so the operator
        // can still pick a txn from the list.

        FeedbackManager.shared.triggerDetectionFeedback(
            isHapticEnabled: AppStorageManager.shared.isHapticEnabled,
            isSoundEnabled: AppStorageManager.shared.isSoundEnabled
        )

        cameraService.disableBarcodeScanning()
        if currentScanType != .stockCount { cameraService.pauseCounting() }

        if let snap = cameraService.captureSnapshot() { self.capturedImage = snap }
        scannedRawValue = newValue

        Task { @MainActor in

            if router.selectedPillScanningType == .FIXED
            {
                switch scanType {
                case .rx_label:
                    if pillScanViewModel.matchesBarcodeFormat(newValue) {
                        cameraState = .rxDetected
                        pillScanViewModel.parseScanData(actualValue: newValue)
                    } else {
                        pillScanViewModel.showToastMessage(text: L10n.BarcodeScan.invalidRxBarcode)
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
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
        if currentScanType != .stockCount { cameraService.resumeCounting() }
        startScanTimeout()
        pillScanViewModel.ndcComparisonResponse = nil
        pillScanViewModel.isNdcEquivalent = false
        pillScanViewModel.showNdcEquivalencePopup = false
        stockCountViewModel.reset()
    }

    // MARK: - Continuous dispense

    /// Called after a FIXED dispense txn is confirmed complete. Instead of navigating
    /// away, it resets everything back to a fresh RX-scan state IN PLACE (camera live,
    /// barcode scanning enabled, scanType = .rx_label) and shows the "Today's Queue"
    /// sheet on top. The operator can then scan an RX (just dismiss the sheet) or pick
    /// a txn from the list to resume it — all without leaving UnifiedCameraView.
    func startContinuousDispense() {
        // If nothing is left to dispense, leave the flow immediately. This must run
        // BEFORE the teardown below: flipping showPillCountPanel/currentControlledStep
        // changes unifiedInstructionText to scanType.instructionText (still .barcode),
        // which fires the speak observer and speaks the barcode prompt on the way out.
        guard hasPendingDispenseTxns() else {
            router.setRoot(to: .authentication(.login(.dashboard(.dashboardHome))))
            return
        }

        // Tear down the just-completed txn's pill-count session.
        showPillCountPanel = false
        isOpenPillScanMode = false
        cameraService.disableBarcodeScanning()
        cameraService.pauseCounting()

        // Reset the RX / NDC popup flags so the next txn gets a fresh false→true
        // transition. onChange observers (e.g. showScannedDrugInfoPopoup driving
        // handleSubstitute) only fire on a transition — if a flag is left true from
        // the just-completed txn, the next scan sets it true with no change and the
        // observer never fires, so the barcode is "accepted" but the flow stalls.
        // Mirrors onAppear's fresh-entry reset.
        pillScanViewModel.showScannedDrugInfoPopoup = false
        pillScanViewModel.showRxFlowPopup = false
        pillScanViewModel.showRxOnHoldPopup = false
        pillScanViewModel.showRxInProgressPopup = false
        pillScanViewModel.showNdcEquivalencePopup = false
        pillScanViewModel.showVerifyStockBottlePopup = false
        pillScanViewModel.ndcMismatchRestartFlow = false
        pillScanViewModel.isNdcEquivalent = false
        pillScanViewModel.ndcComparisonResponse = nil
        pillScanViewModel.isDrugFound = nil

        // Clear all per-transaction state so the next txn starts clean.
        pillScanViewModel.resetScanningState()
        pillScanViewModel.selectedTransaction = nil
        pillScanViewModel.currentTransaction = nil
        pillScanViewModel.currentTransactionTransactionDetails = nil
        pillScanViewModel.scannedRxData = nil
        pillScanViewModel.fetchedRxTransaction = nil
        pillScanViewModel.note = ""
        pillScanViewModel.selectedBucket = ""
        pillScanViewModel.currentControlledStep = .scan
        pillScanViewModel.currentControlledTargetCount = nil
        pillScanViewModel.capturedVialImage = nil
        pillScanViewModel.vialCapturedImagePath = nil
        userViewModel.currentTransactionTxnId = nil

        scannedRawValue = nil
        capturedImage = nil
        hasInitializedStep = false
   

        // Surface the queue (there's pending work — checked at the top). Scanning an
        // RX dismisses the sheet (see onChange below); picking a row resumes that txn.
        showDispenseQueueSheet = true
        cameraState = .scanning

        // Back to RX-label scan, ready underneath the sheet.
        scanType = .rx_label
        cameraService.start()
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
        pillScanViewModel.resetTrayColorTracking()
    }

    /// True when there are pending FIXED dispense txns waiting. Builds the same list
    /// the queue sheet's `reload()` produces: FIXED, batch_id == 0, status != ON_HOLD.
    private func hasPendingDispenseTxns() -> Bool {
        let userId = AppStorageManager.shared.userId ?? ""
        guard let user = UserStore.shared.fetchByUserId(userId) else {
            return false
        }

        let fixed = TransactionStore.shared.fetchPartial(for: user, countType: .FIXED)
        let fresh = fixed
            .filter { $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue }
            .sorted { $0.created_at < $1.created_at }

        return !fresh.isEmpty
    }

    /// Resume a txn picked from the queue sheet — mirrors the `.resumeCount` branch of
    /// `onAppear`, but in place (no navigation). Reflects whatever state the txn is in.
    func resumeSelectedTransactionInline(_ txn: PillCountTransactionEntity) {
        showDispenseQueueSheet = false

        let countType: CountType =
            txn.count_type?.uppercased() == CountType.REGULAR.rawValue ? .REGULAR : .FIXED
        router.selectedPillScanningType = countType
        userViewModel.currentTransactionTxnId = txn.txn_id
        pillScanViewModel.selectedTransaction = txn

        // If the NDC isn't verified yet, fall back to the barcode-scan state so the
        // operator scans the bottle first (same as the dashboard resume → .barcode path).
        guard txn.is_ndc_verfied else {
            scanType = .barcode
            pillScanViewModel.currentTransaction = txn
            showPillCountPanel = false
            cameraState = .scanning
            scannedRawValue = nil
            capturedImage = nil
            cameraService.start()
            cameraService.resetBarcodeScanState()
            cameraService.enableBarcodeScanning()
            cameraService.pauseCounting()
            return
        }

        // NDC verified — resume counting directly.
        scanType = .resumeCount
        pillScanViewModel.currentTransaction = txn
        pillScanViewModel.getControlledStep(pillCountTxn: txn)
        pillScanViewModel.getAllTransactionDetailsOfTheCurrentTransaction()
        pillScanViewModel.addCurrentOpenPillCount = 0
        hasInitializedStep = true

        showPillCountPanel = true
        cameraService.start()
        cameraService.disableBarcodeScanning()
        if pillScanViewModel.currentControlledStep != .vial {
            cameraService.resumeCounting()
        } else {
            cameraService.pauseCounting()
        }
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

        // Re-enable Add quickly — a short lockout only guards against an accidental
        // double-tap, it shouldn't make the operator wait. The success animation
        // runs its own ~2.5s lifecycle and is dismissed separately below.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isAddDisabled = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
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
        // Newly added to skip completion popup
        if pillScanViewModel.capturedVialImage != nil {
            pillScanViewModel.capturedVialImage = nil
            pillScanViewModel.vialCapturedImagePath = nil
            cameraService.start()
            cameraService.rebindPreviewLayer()
            cameraService.resetInactivityTimer()
        }
        pillScanViewModel.handleStepCompletion()
//        showStepCompletionPopup = true
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
//            showStepCompletionPopup = true
            // Newly added to skip completion popup
            if pillScanViewModel.capturedVialImage != nil {
                pillScanViewModel.capturedVialImage = nil
                pillScanViewModel.vialCapturedImagePath = nil
                cameraService.start()
                cameraService.rebindPreviewLayer()
                cameraService.resetInactivityTimer()
            }
            pillScanViewModel.handleStepCompletion()
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

    /// Called by the Clear button — clears the detail slot and refreshes the list.
    func clearScannedDetails() {
        stockCountViewModel.scannedDrugData = nil
        stockCountViewModel.selectedGroupedTransaction = nil
        stockCountViewModel.showStockCountScannedDetails = false
        stockCountViewModel.suppressListReload = false
        stockCountViewModel.reloadAllState()
        btScannerFocusTrigger += 1
    }

    /// Called by the Add button — dismisses the details panel and refreshes the list.
    func dismissScannedDetails() {
        stockCountViewModel.flushPendingBottleCount()
        stockCountViewModel.suppressListReload = false
        stockCountViewModel.reset()
        stockCountViewModel.reloadAllState()
        btScannerFocusTrigger += 1
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

        // Decode to extract GTIN for same-drug detection.
        // BT scanners often emit a plain NDC (no GS1 envelope), so fall back to
        // stripping non-digit characters from rawValue when the decoder finds nothing.
        let decoded = stockCountViewModel.decoder.decode(rawValue)
        let rawDigitsOnly = rawValue.components(separatedBy: .decimalDigits.inverted).joined()
        let scannedGtin: String = {
            if let g = decoded.gtin, !g.isEmpty { return g }
            if rawDigitsOnly.count >= 8 && rawDigitsOnly.count <= 14 { return rawDigitsOnly }
            return rawValue
        }()

        // Check if this is the same drug already showing
        let isSameNdc: Bool = {
            guard let drug = stockCountViewModel.scannedDrugData, !drug.ndc.isEmpty else { return false }
            return drug.gtin == scannedGtin || drug.ndc == scannedGtin
        }()

        if isSameNdc {
            // Same barcode held in front — increment sealed bottle count, commit immediately.
            stockCountViewModel.pendingBottleCount += 1
            await performStockCountAdd()
        } else {
            // Different NDC — commit any pending drug first, then fetch and auto-add the new one.
            await autoCommitPendingStockScan()
            await stockCountViewModel.getScannedDrugData(rawValue: rawValue)
            // Auto-add the scanned drug without requiring a manual tap.
            if stockCountViewModel.scannedDrugData != nil {
                await performStockCountAdd()
            }
        }

        // Always re-enable scanning so any barcode (including a new one) can be read.
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
        btScannerFocusTrigger += 1
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
        // Enable pill detection immediately so the tray overlay and count ring
        // are live while the user positions the pill tray before scanning the barcode.
        cameraService.resumeCounting()
        // Voice is handled by the unified .onChange(of: unifiedInstructionText) observer.
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
            title: L10n.Stock.endBatchTitle,
            message: stockHasNoCount ? L10n.Stock.noCountEndBatchMessage : nil,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes,
            onCancel: { showStockEndBatchPopUp = false },
            onConfirm: { confirmStockEndBatch() }
        )
    }

    var stockNoteOptionPopup: some View {
        NotePopupView(
            title: L10n.Stock.addNoteQuestion,
            text: $stockCountViewModel.note,
            errorMessage: stockNoteError,
            primaryTitle: L10n.Common.yes,
            primaryAction: {
                if stockCountViewModel.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stockNoteError = L10n.PillCount.pleaseAddNote
                    return
                }
                stockNoteError = nil
                showStockNoteOptions = false
                showStockEndBatchPopUp = true
            },
            secondaryTitle: L10n.Common.skip,
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



// MARK: - View modifier helpers (type-checker relief)

private extension View {

    /// Wires the six BT focus-trigger onChange modifiers as a separate
    /// sub-expression so the Swift type-checker doesn't time out on the
    /// combined rootContent chain.
    func withBtFocusTriggers(
        showPillCountPanel: Bool,
        pillScanViewModel: PillScanViewModel,
        stockCountViewModel: StockCountViewModel,
        showManualEntryPopup: Bool,
        btScannerFocusTrigger: Binding<Int>
    ) -> some View {
        self
            .onChange(of: pillScanViewModel.showRxFlowPopup) { _, showing in
                if !showing && !showPillCountPanel { btScannerFocusTrigger.wrappedValue += 1 }
            }
            .onChange(of: pillScanViewModel.showNdcEquivalencePopup) { _, showing in
                if !showing && !showPillCountPanel { btScannerFocusTrigger.wrappedValue += 1 }
            }
            .onChange(of: stockCountViewModel.showStockCountScannedDetails) { _, showing in
                if !showing && !showPillCountPanel { btScannerFocusTrigger.wrappedValue += 1 }
            }
            .onChange(of: stockCountViewModel.showScannedNdcDoesNotMatch) { _, showing in
                if !showing && !showPillCountPanel { btScannerFocusTrigger.wrappedValue += 1 }
            }
            .onChange(of: showManualEntryPopup) { _, showing in
                if !showing && !showPillCountPanel { btScannerFocusTrigger.wrappedValue += 1 }
            }
    }
}
