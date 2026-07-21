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
    /// Dispense transaction id passed via the route. When set, the screen sets
    /// up the scan session for that transaction in `onAppear`. nil for flows
    /// that don't target an existing txn (e.g. fresh rx_label).
    let dispenseTxnId: Int64?
    /// Stock-count batch id to resume (route payload). nil unless resuming.
    let stockBatchId: Int64?
    /// Bucket id for a brand-new stock-count batch (route payload). nil unless new.
    let newBatchBucketId: String?
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

    init(
        currentScanType: ScanType,
        dispenseTxnId: Int64? = nil,
        stockBatchId: Int64? = nil,
        newBatchBucketId: String? = nil
    ) {
        self.currentScanType = currentScanType
        self.dispenseTxnId = dispenseTxnId
        self.stockBatchId = stockBatchId
        self.newBatchBucketId = newBatchBucketId
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
    /// Shown when an RX label is scanned but HL7/PMS is disabled for this account.
    /// The scan is blocked entirely — no parse/proceed logic runs.
    @State var showHl7UnavailablePopup: Bool = false
    /// Bumped on transactionsDidChange while the Rx sheet is showing, to force the
    /// sheet content closure to re-read scannedRxDrugMaster.drug_image once the
    /// async catalog-image download finishes.
    @State var rxSheetImageRefreshTick: Int = 0
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

    // (Same-scan cooldown removed — the camera-level barcodeLockMissThreshold debounce
    // now prevents a held-steady barcode from re-firing, making the view-layer cooldown unnecessary.)

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
            .customPopup(isPresented: $showHl7UnavailablePopup, dismissOnBackgroundTap: false) { hl7UnavailablePopup }
            .customPopup(isPresented: $pillScanViewModel.showHazardousTrayPopup) { hazardousTrayPopup }
            .customPopup(isPresented: $pillScanViewModel.showHazardousTraySubstitutePopup) { hazardousTraySubstitutePopup }
            .customPopup(isPresented: $pillScanViewModel.showAddBottlePopup) { showAddBottlePopupContent }
            .customPopup(isPresented: $pillScanViewModel.showReplaceBottlePopup) { showReplaceBottlePopupContent }
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
        // Commented for now
//            .overlay {
//                if showSuccessAnimation {
//                    SuccessAnimationView(count: lastAddedCount, color: appColors.secondary)
//                        .allowsHitTesting(false)
//                }
//            }
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

    // ── OLD pill-count bottom-sheet UI (replaced by the new full-screen overlay) ──
    // Kept (commented out) intentionally — do not delete while the new UI is validated.
//    private var rootWithPillCountSheet: some View {
//        rootWithBarcodePopups
//            .bottomSheet(
//                isPresented: $showPillCountPanel,
//                dismissOnBackgroundTap: false,
//                showDim: false,
//                portraitHeight: pillCountSheetHeight,
//                landscapeWidth: UIDevice.current.userInterfaceIdiom == .pad ? nil : 280
//            ) {
//                ZStack {
//                    darkAppColors.secondaryBackground.opacity(0.6)
//                    if pillScanViewModel.currentControlledStep == .vial {
//                        vialControlBottomView
//                            .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    } else {
//                        controlsContent
//                    }
//                }
//                .environmentObject(darkAppColors)
//            }
//    }

    // ── NEW pill-count UI ──────────────────────────────────────────────────────
    // Full-screen overlay over the live camera (no bottom sheet). Non-vial steps
    // show the new layout (top info bar + movable count ring + target progress bar +
    // steps row + "View all counts"). The vial step shows just its three icons
    // (redo / capture / done) in the same bottom area — no background. Logic is
    // unchanged; the same handlers are wired.
    private var rootWithPillCountSheet: some View {
        rootWithBarcodePopups
            .overlay {
                // Hidden while the inactivity "Resume" overlay (in UnifiedCameraLayout,
                // the layer below) is up — so Resume stays the topmost, tappable control.
                if showPillCountPanel && !cameraService.isPausedDueToInactivity {
                    Group {
                        if pillScanViewModel.currentControlledStep == .vial {
                            VStack {
                                Spacer()
                                vialControlBottomView
                                    .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 14)
                            }
                        } else {
                            PillCountLayout(
                                pillScanViewModel: pillScanViewModel,
                                cameraService: cameraService,
                                isDispense: router.selectedPillScanningIsDispense ?? true,
                                isLandscape: isLandscape,
                                isAddDisabled: isAddDisabled,
                                instructionText: overlayInstructionText,
                                showGloveIndicator: (currentScanType != .stockCount || isOpenPillScanMode)
                                    && cameraService.isGloveDetectionEnabled,
                                isOpenPillScanMode: isOpenPillScanMode,
                                onBack: { handleBack() },
                                onAdd: { handleAdd() },
                                onAllDone: { handleComplete() },
                                onShowDetailGrid: { showDetailGrid = true }
                            )
                        }
                    }
                    .environmentObject(darkAppColors)
                    .ignoresSafeArea()
                }
            }
    }

    private var rootWithBarcodePopups: some View {
        rootContent
            .bottomSheet(
                isPresented: $pillScanViewModel.showRxFlowPopup,
                showDim: false,
                onDismiss: {
                    pillScanViewModel.showRxFlowPopup = false
                    pillScanViewModel.fetchedRxTransaction = nil
                    restartFlow()
                }
            ) {
                // Drug image for a brand-new Rx downloads async in the background
                // (DrugCatalogStore) and only lands on scannedRxDrugMaster afterwards.
                // Bump this on transactionsDidChange while the sheet is up so the
                // content closure re-reads scannedRxDrugMaster and picks up the image.
                let _ = rxSheetImageRefreshTick

                RxDetailsSheetContent(
                    onCancel: {
                        pillScanViewModel.showRxFlowPopup = false
                        pillScanViewModel.fetchedRxTransaction = nil
                        restartFlow()
                    },
                    onProceed: {
                        Task {
                            await pillScanViewModel.proceedFromRxScan()
                            userViewModel.currentTransactionTxnId = pillScanViewModel.selectedTransaction?.txn_id
                            scanType = .barcode
                            restartFlow()
                        }
                    },
                    drugName: pillScanViewModel.fetchedRxTransaction?.drug?.drug_name
                        ?? pillScanViewModel.scannedRxData?.drugName ?? "-",
                    quantity: pillScanViewModel.fetchedRxTransaction?.target_count.description
                        ?? pillScanViewModel.scannedRxData?.qty ?? "-",
                    ndcNumber: pillScanViewModel.fetchedRxTransaction?.drug?.ndc
                        ?? pillScanViewModel.scannedRxData?.ndcNo ?? "-",
                    bucket: pillScanViewModel.fetchedRxTransaction?.bucket_id
                        ?? (pillScanViewModel.selectedBucket.isEmpty ? "NORMAL" : pillScanViewModel.selectedBucket),
                    rxNumber: pillScanViewModel.fetchedRxTransaction?.rx_no
                        ?? pillScanViewModel.scannedRxData?.rxNo ?? "-",
                    strength: pillScanViewModel.fetchedRxTransaction?.drug?.strength
                        ?? pillScanViewModel.scannedRxDrugMaster?.strength ?? "-",
                    form: pillScanViewModel.fetchedRxTransaction?.drug?.dosage_form
                        ?? pillScanViewModel.scannedRxDrugMaster?.dosage_form ?? "-",
                    drugImagePath: pillScanViewModel.fetchedRxTransaction?.drug?.drug_image
                        ?? pillScanViewModel.scannedRxDrugMaster?.drug_image
                )
                .environmentObject(appColors)
            }
            .onReceive(TransactionStore.shared.transactionsDidChange.receive(on: DispatchQueue.main)) {
                if pillScanViewModel.showRxFlowPopup { rxSheetImageRefreshTick &+= 1 }
            }
            .bottomSheet(
                isPresented: $pillScanViewModel.showVerifyStockBottlePopup,
                dismissOnBackgroundTap: false,
                showDim: false,
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
                    drugIsHazardous: pillScanViewModel.currentDrug?.is_hazardous == true
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
                syncGloveDetectionEnabled()
                // New transaction (e.g. continuous dispense): re-arm tray-colour
                // sampling so the same physical tray re-emits its colour and the
                // hazardous-tray check/marking runs for this transaction too.
                cameraService.resetTrayColorSampling()
                pillScanViewModel.resetTrayColorTracking()
            }
            // currentTransaction only covers the FIXED/REGULAR dispense flow — open-pill
            // scan and stock-count flows carry their drug on currentStockTxn /
            // pendingOpenBottleDrug instead (see PillScanViewModel.currentDrug), so the
            // hazardous gate must also react to those two changing.
            .onChange(of: pillScanViewModel.currentStockTxn) { _, _ in
                syncGloveDetectionEnabled()
            }
            .onChange(of: pillScanViewModel.pendingOpenBottleDrug) { _, _ in
                syncGloveDetectionEnabled()
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
                router.setRoot(to: .authentication(.login(.dashboard(.dashboardHome))))
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
            if pillScanViewModel.currentControlledStep != .vial {
                cameraService.resumeCounting()
                cameraService.enableBottleRescanListening()
            } else {
                enableVialRxScanning()
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
                // Re-arm barcode scanning so the operator can hold the dispensing
                // vial's RX label in frame and have it auto-captured when the RX
                // matches this transaction (handleScannedCode → handleVialRxScan).
                enableVialRxScanning()
                // Bottle rescan only applies to active counting steps, not the vial photo step.
                cameraService.disableBottleRescanListening()
            } else {
                // Leaving the vial step — keep barcode/QR scanning live across every
                // pill-counting step via the bottle-rescan channel (coexists with ML
                // counting, unlike enableBarcodeScanning()), just resume ML counting.
                cameraService.resumeCounting()
                cameraService.enableBottleRescanListening()
            }
        }
        .onChange(of: cameraService.bottleRescanCode) { _, code in
            guard !code.isEmpty else { return }
            pillScanViewModel.handleBottleRescan(rawBarcode: code, snapshot: cameraService.captureSnapshot())
        }
        .onChange(of: pillScanViewModel.showAddBottlePopup) { _, showing in
            handleBottleConfirmationPopupVisibility(showing)
        }
        .onChange(of: pillScanViewModel.showReplaceBottlePopup) { _, showing in
            handleBottleConfirmationPopupVisibility(showing)
        }
        .onChange(of: unifiedInstructionText) { _, newText in
            speakInstruction(newText)
        }
    }

    // MARK: - Computed helpers

    var controlledStepInstruction: String {
        if pillScanViewModel.currentTransaction?.is_dispense == false {
            return L10n.Controlled.regularTargetReverification
        }
        if isOpenPillScanMode && pillScanViewModel.currentControlledStep == .targetVerification {
            return L10n.Controlled.countOpenPills
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

    // OLD pill-count controls (replaced by PillCountLayout). Kept commented out.
//    private var controlsContent: some View {
//        BottomControlsView(
//            isLandscape: isLandscape,
//            pillScanViewModel: pillScanViewModel,
//            cameraService: cameraService,
//            appColors: darkAppColors,
//            isAddButtonDisabled: isAddDisabled,
//            onAddPill: { handleAdd() },
//            onComplete: { handleComplete() },
//            onReset: { showDeleteAllTransactionDetailsPopup = true },
//            onShowDetailGrid: { showDetailGrid = true },
//            showTransactionDetails: $showTransactionHistory,
//            isPaused: $isPaused
//        )
//    }

    private var vialControlBottomView: some View {
        VialBottomContentView()
            .environmentObject(cameraService)
            .environmentObject(darkAppColors)
    }
}

// MARK: - Lifecycle
extension UnifiedCameraView {

    /// Recomputes the glove-detection gate from whichever drug source is active
    /// for the current flow — currentTransaction (FIXED/REGULAR dispense),
    /// currentStockTxn (stock-count), or pendingOpenBottleDrug (open-pill scan).
    /// See PillScanViewModel.currentDrug for the same fallback chain.
    func syncGloveDetectionEnabled() {
        cameraService.isGloveDetectionEnabled =
            (pillScanViewModel.currentDrug?.is_hazardous == true)
            && AppStorageManager.shared.isHazardousDrugSetting
    }

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
        // Same reasoning for the glove gate: if the drug is already set when this
        // view appears (resume, or multi-bottle-dispense/open-pill-scan handing off
        // a pre-selected drug), the onChange handlers below never fire on the value
        // already present, so isGloveDetectionEnabled would stay stuck at its default.
        syncGloveDetectionEnabled()
        cameraState = .scanning
        scannedRawValue = nil
        capturedImage = nil
        hasInitializedStep = false
        scanType = currentScanType

        // Resume/start an existing dispense transaction. The route carries the
        // id; the VM fetches it and sets `selectedTransaction`. This must run
        // before the transaction-clearing and resume logic below, which read
        // `selectedTransaction` / `currentTransactionTxnId`.
        if let dispenseTxnId,
           let setup = pillScanViewModel.startDispenseCount(txnId: dispenseTxnId) {
            userViewModel.currentTransactionTxnId = dispenseTxnId
            router.selectedPillScanningIsDispense = setup.isDispense
        }

        // Set up the stock-count session from the route payload (resume an
        // existing batch, or start a new one for a bucket). Runs after
        // `reset()`, which intentionally preserves currentBatch/pendingBucketId.
        if let stockBatchId {
            stockCountViewModel.startStockCount(batchId: stockBatchId)
            router.selectedPillScanningIsDispense = false
        } else if let newBatchBucketId {
            stockCountViewModel.startNewBatch(bucketId: newBatchBucketId)
            router.selectedPillScanningIsDispense = false
        }

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
            // Start directly — start() runs on the session queue (serialized) and
            // re-attaches the preview itself, so the extra main-queue hop is unneeded
            // and only delayed the first frame.
            cameraService.start()
            cameraService.cancelInactivityTimer()
            initializeTransaction()
            if pillScanViewModel.currentControlledStep != .vial {
                cameraService.resumeCounting()
            }
        } else {
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

    func onDisappear() {
        lastSpokenInstruction = ""
        scanTimeoutTask?.cancel()
        cameraService.disableBarcodeScanning()
        cameraService.disableBottleRescanListening()
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

        // Vial step auto-capture: while the pill-count panel is on the vial step, a
        // scanned barcode is the dispensing vial's RX label — not an RX/NDC scan.
        // Match it against the transaction and capture; never fall through to the
        // normal RX/NDC parse flow below.
        if showPillCountPanel && pillScanViewModel.currentControlledStep == .vial {
            handleVialRxScan(newValue)
            return
        }

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

            if router.selectedPillScanningIsDispense == true
            {
                switch scanType {
                case .rx_label:
                    guard AppStorageManager.shared.isPmsIntegrated else {
                        cameraState = .rxDetected
                        showHl7UnavailablePopup = true
                        return
                    }
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
                // Open pill barcode matched — start pill counting.
                // Barcode scanning stays enabled across scanning -> pillCounting so
                // GS1 metadata capture doesn't drop mid-transition.
                showPillCountPanel = true
                initializeTransaction()
                return
            }
            scanTimeoutTask?.cancel()
            showPillCountPanel = true
            initializeTransaction()
        case false:
            showManualEntryPopup = true
        default:
            showManualEntryPopup = false
        }
    }

    /// Bottle rescan add/replace confirmation is shown as a popup over the live
    /// camera view. Pause counting while it's up so the frame doesn't keep
    /// advancing under the dialog; on dismiss (confirm OR cancel) resume — the
    /// snapshot for a confirmed bottle is grabbed at the moment of confirm
    /// (see showAddBottlePopupContent/showReplaceBottlePopupContent), not here.
    func handleBottleConfirmationPopupVisibility(_ showing: Bool) {
        guard currentScanType != .stockCount else { return }
        if showing {
            cameraService.pauseCounting()
        } else {
            cameraService.resumeCounting()
        }
    }

    func initializeTransaction() {
        guard currentScanType != .stockCount || isOpenPillScanMode else { return }

        // Open-pill (stock-count) counting has no PillCountTransactionEntity backing it —
        // the drug/NDC lives on currentStockTxn instead — and is always a single free-count
        // step (no container/vial controlled-drug machinery), so skip the FIXED-dispense
        // txn lookup and step derivation entirely.
        if isOpenPillScanMode {
            pillScanViewModel.currentControlledStep = .targetVerification
            pillScanViewModel.currentControlledTargetCount = 0
            pillScanViewModel.addCurrentOpenPillCount = 0
            cameraService.resumeCounting()
            return
        }

        Task {
            if pillScanViewModel.currentTransaction == nil {
                let txnId = userViewModel.currentTransactionTxnId ?? 0
                await pillScanViewModel.getCurrentTransaction(txnId: txnId)
            }
            await MainActor.run {
                pillScanViewModel.getControlledStep(pillCountTxn: pillScanViewModel.currentTransaction)
                pillScanViewModel.addCurrentOpenPillCount = 0
                pillScanViewModel.stageFirstBottleIfNeeded(rawBarcode: scannedRawValue)
                if pillScanViewModel.currentControlledStep == .vial {
                    cameraService.pauseCounting()
                    enableVialRxScanning()
                } else {
                    cameraService.resumeCounting()
                    cameraService.enableBottleRescanListening()
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

        let fixed = TransactionStore.shared.fetchPartial(for: user, isDispense: true)
        let fresh = fixed
            .filter { $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue }
            .sorted { $0.created_at < $1.created_at }

        return !fresh.isEmpty
    }

    /// Resume a txn picked from the queue sheet — mirrors the `.resumeCount` branch of
    /// `onAppear`, but in place (no navigation). Reflects whatever state the txn is in.
    func resumeSelectedTransactionInline(_ txn: PillCountTransactionEntity) {
        showDispenseQueueSheet = false

        router.selectedPillScanningIsDispense = txn.is_dispense
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
            cameraService.enableBottleRescanListening()
        } else {
            cameraService.pauseCounting()
            enableVialRxScanning()
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
            let activeBottle = txn.flatMap { pillScanViewModel.activeBottle(txnId: $0.txn_id) }

            let finalImage = processed.addingMetadataOverlay(
                ndc: txn?.drug?.ndc ?? "",
                substituteNdc: txn?.substitueDrug?.ndc ?? "",
                workflowStep: pillScanViewModel.currentControlledStep.rawValue,
                count: cameraService.stableCount,
                targetCount: txn?.target_count,
                timestamp: timestamp,
                userInitials: user,
                geolocation: locationService.locationString,
                rx: txn?.rx_no ?? "",
                fileSizeKB: fileSizeKB,
                lotNumber: activeBottle?.lotNumber,
                expirationDate: activeBottle?.expirationDate,
                serialNumber: activeBottle?.serialNumber
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
                && pillScanViewModel.currentTransaction?.is_dispense == true {
                showNoteOption = true
            } else {
                showConfirmCompletionPopup = true
            }
            return
        }
        // Newly added to skip completion popup.
        // Clearing capturedVialImage removes the full-screen vial still overlay and
        // reveals the live feed. The session was never stopped (vial only freezes
        // counting), so no start()/rebind is needed — just reset the inactivity timer.
        if pillScanViewModel.capturedVialImage != nil {
            pillScanViewModel.capturedVialImage = nil
            pillScanViewModel.vialCapturedImagePath = nil
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
            // Newly added to skip completion popup.
            // Clearing capturedVialImage removes the full-screen vial still overlay and
            // reveals the live feed. The session was never stopped (vial only freezes
            // counting), so no start()/rebind is needed — just reset the inactivity timer.
            if pillScanViewModel.capturedVialImage != nil {
                pillScanViewModel.capturedVialImage = nil
                pillScanViewModel.vialCapturedImagePath = nil
                cameraService.resetInactivityTimer()
            }
            pillScanViewModel.handleStepCompletion()
        }
    }

    // MARK: - Vial RX auto-capture

    /// Arms barcode scanning for the vial step so the dispensing vial's RX label
    /// can be read and matched. Clears any stale scanned value first so a value
    /// left over from an earlier scan doesn't immediately re-fire.
    func enableVialRxScanning() {
        guard currentScanType != .stockCount else { return }
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
    }

    /// Handles a barcode read while on the vial step. The barcode is the dispensing
    /// vial's RX label: extract its RX number and compare to the current
    /// transaction's rx_no. On a match, auto-capture the still and run the done
    /// path (advances the step). On a mismatch — a different RX label — surface
    /// "Incorrect RX label found" and keep scanning.
    func handleVialRxScan(_ rawValue: String) {
        // Already captured (manual or auto) — ignore further reads until redo.
        guard pillScanViewModel.capturedVialImage == nil else { return }

        let expectedRx = pillScanViewModel.currentTransaction?.rx_no?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scannedRx = pillScanViewModel.extractRxNo(from: rawValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !expectedRx.isEmpty, !scannedRx.isEmpty,
              scannedRx.compare(expectedRx, options: .caseInsensitive) == .orderedSame else {
            // A barcode was read but it isn't this transaction's RX label.
            FeedbackManager.shared.triggerDetectionFeedback(
                isHapticEnabled: AppStorageManager.shared.isHapticEnabled,
                isSoundEnabled: AppStorageManager.shared.isSoundEnabled
            )
            pillScanViewModel.showToastMessage(text: L10n.PillCount.incorrectRxLabel)
            // Re-arm so the operator can present the correct label.
            enableVialRxScanning()
            return
        }

        // RX matches — capture and complete the vial step automatically.
        FeedbackManager.shared.triggerDetectionFeedback(
            isHapticEnabled: AppStorageManager.shared.isHapticEnabled,
            isSoundEnabled: AppStorageManager.shared.isSoundEnabled
        )
        cameraService.disableBarcodeScanning()
        autoCaptureVialAndDone()
    }

    /// Captures the live still into the vial image slot and immediately runs the
    /// done path. Mirrors VialBottomContentView.captureVial() + doneVial() so the
    /// auto path produces the same state as a manual capture-then-done.
    private func autoCaptureVialAndDone() {
        guard let image = cameraService.captureSnapshot() else {
            // Capture failed — re-arm scanning so the operator can retry.
            enableVialRxScanning()
            return
        }
        let normalized = image.normalized()
        pillScanViewModel.capturedVialImage = normalized
        guard let path = PhotoFileManager.shared.saveImage(normalized) else {
            // Couldn't persist — clear the in-memory still and re-arm.
            pillScanViewModel.capturedVialImage = nil
            enableVialRxScanning()
            return
        }
        pillScanViewModel.vialCapturedImagePath = path
        pillScanViewModel.addOrReplaceVialTransactionDetail(imagePath: path)
        // Fires the vialDoneTriggered observer → handleVialDone(), which advances
        // the step (and clears the captured still as part of that flow).
        pillScanViewModel.vialDoneTriggered = true
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
        if stockCountViewModel.currentBatch?.req_id_from_pms != nil,
           let stockTxn = stockCountViewModel.stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: drug.ndc) {
            pillScanViewModel.updatePmsTxnCount(
                stockTxn: stockTxn,
                containerStatus: scannedBottleContainerStatus,
                scannedQty: Int(drug.quantity)
            )
            stockCountViewModel.committedStockTxnId = stockTxn.stock_txn_id
            stockCountViewModel.committedBottleId = pillScanViewModel.currentBottleInfo?.bottle_id
        } else {
            await pillScanViewModel.createTxnForBatchFromScan(
                rawValueFromBarcodeOrQr: drug.rawBarcode,
                ndc: drug.ndc,
                drugName: drug.drugName,
                quantity: Int32(drug.quantity),
                batchId: batchId,
                containerStatus: scannedBottleContainerStatus,
                bottleCount: stockCountViewModel.pendingBottleCount
            )
            stockCountViewModel.committedStockTxnId = pillScanViewModel.currentStockTxn?.stock_txn_id
            stockCountViewModel.committedBottleId = pillScanViewModel.currentBottleInfo?.bottle_id
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

        #if DEBUG
        let expiryString = decoded.expirationDate.map {
            ISO8601DateFormatter().string(from: $0)
        } ?? "-"
        print("🔍 STOCK SCAN DECODE")
        print("    rawValue      : \(rawValue)")
        print("    gtin          : \(decoded.gtin ?? "-")")
        print("    serialNumber  : \(decoded.serialNumber ?? "-")")
        print("    lotNumber     : \(decoded.lotNumber ?? "-")")
        print("    expirationDate: \(expiryString)")
        #endif

        // Only a real GS1 AI(01) decode is a valid GTIN — a bare NDC/UPC digit
        // string is NOT a GTIN (no packaging-indicator digit, no check digit) and
        // must never be written to DrugMasterEntity.gtin, or later rescans that
        // decode the real GS1 GTIN will never match what's stored.
        let scannedGtin: String = decoded.gtin ?? rawValue

        // Check if this is the same drug already showing
        let isSameNdc: Bool = {
            guard let drug = stockCountViewModel.scannedDrugData, !drug.ndc.isEmpty else { return false }
            return drug.gtin == scannedGtin || drug.ndc == scannedGtin
        }()

        if isSameNdc {
            // Same NDC scanned again — the camera-level lock (barcodeLockMissThreshold)
            // already guarantees this fires only when the barcode genuinely left the
            // frame and came back. Increment the bottle count and commit.
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

    /// In open pill mode: scan the barcode to confirm/find the drug, then hand off to pill
    /// counting. If the scanned NDC doesn't match the expected one, show an error.
    func handleOpenPillBarcodeScan(_ rawValue: String) async {
        // Do NOT create the batch here — the batch, StockTxn, and BottleInfo rows are all
        // created together on Proceed (createOpenedBottleFromPendingScan). Scanning the NDC
        // to start a count must not persist anything the user could abandon mid-count.
        let batchId = stockCountViewModel.currentBatch?.batch_id

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

        // Resolve the drug only — no Batch/StockTxn/BottleInfo rows yet. All three are
        // created together once counting finishes and the user taps Proceed.
        await pillScanViewModel.resolveStockTxnForOpenPillScan(
            rawValueFromBarcodeOrQr: rawValue,
            ndc: drug.ndc,
            drugName: drug.drugName,
            quantity: drug.quantity,
            batchId: batchId
        )
    }

    /// Called when a new barcode is scanned while a drug's details are showing.
    /// Treats the current details as "Add tapped" — refreshes list then clears for next scan.
    func autoCommitPendingStockScan() async {
        guard stockCountViewModel.scannedDrugData != nil else { return }
        if stockCountViewModel.committedStockTxnId != nil {
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
        // The same NDC barcode was likely just scanned for the sealed-bottle add —
        // release the same-barcode lock so re-scanning it now for pill counting fires.
        cameraService.forceReleaseBarcodeLock()
        cameraService.enableBarcodeScanning()
        // Enable pill detection immediately so the tray overlay and count ring
        // are live while the user positions the pill tray before scanning the barcode.
        cameraService.resumeCounting()
        // Re-focus the hidden BT-scanner input field. After a sealed-bottle scan the
        // field can be left unfocused (nothing else re-requests focus — the
        // showStockCountScannedDetails/showManualEntryPopup observers only fire on an
        // actual value CHANGE, and those flags are often already false here), so BT
        // scanner input silently goes nowhere until the screen is fully re-entered.
        btScannerFocusTrigger += 1
        // Voice is handled by the unified .onChange(of: unifiedInstructionText) observer.
        // Do NOT show the pill count panel here — it opens after the barcode is
        // scanned and handleDrugFoundState receives isDrugFound == true.
    }


    func handleBack() {
        if isOpenPillScanMode && pillScanViewModel.currentControlledStep == .targetVerification {
            showPillCountPanel = false
            scanType = .stockCount
            pillScanViewModel.currentControlledStep = .scan
            pillScanViewModel.pendingOpenBottleLot = nil
            pillScanViewModel.pendingOpenBottleExpiry = nil
            pillScanViewModel.pendingOpenBottleSerial = nil
            pillScanViewModel.pendingOpenBottleDrug = nil
            pillScanViewModel.pendingOpenBottleDrugId = nil
            pillScanViewModel.currentStockTxn = nil
            pillScanViewModel.addCurrentOpenPillCount = 0
            // Must clear these — otherwise the next barcode scan on the Stock Count
            // screen still routes through the open-pill path (handleStockCountScan
            // checks isOpenPillScanMode first) and can silently create a bogus
            // opened BottleInfoEntity row for whatever NDC gets scanned next.
            isOpenPillScanMode = false
            openPillScanNdc = ""
            scannedBottleContainerStatus = .sealed
            restartFlow()
        } else {
            router.navigateBack()
        }
    }

    func handleOpenPillCountComplete() {
        guard isOpenPillScanMode,
              pillScanViewModel.pendingOpenBottleDrugId != nil else { return }
        let loosePills = pillScanViewModel.addCurrentOpenPillCount
        pillScanViewModel.createOpenedBottleFromPendingScan(
            existingBatch: stockCountViewModel.currentBatch,
            bucketId: stockCountViewModel.pendingBucketId,
            loosePillCount: loosePills
        )
        // The batch may have just been created for real (first count of the session with
        // no prior sealed scan) — make sure stockCountViewModel tracks it from here on.
        if stockCountViewModel.currentBatch == nil {
            stockCountViewModel.currentBatch = pillScanViewModel.currentStockTxn?.batch
        }

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
            message: stockHasNoCount ? L10n.Stock.noCountEndBatchMessage : L10n.Stock.confirmEndBatch,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes,
            onCancel: { showStockEndBatchPopUp = false },
            onConfirm: { confirmStockEndBatch() }
        )
        // Force the standard (light) palette so the dialog's buttons match every
        // other ConfirmationDialogue. Without this it inherits the camera screen's
        // forced-dark appColors, making the Yes/No buttons render with a different
        // background/text colour than the rest of the app.
        .environmentObject(appColors)
    }

    var hl7UnavailablePopup: some View {
        ConfirmationDialogue(
            title: L10n.Menu.featureNotAvailableTitle,
            message: L10n.Menu.featureNotAvailableMessage,
            cancelButtonText: "",
            confirmButtonText: L10n.Common.ok,
            showSingleConfirmButton: true,
            onCancel: {},
            onConfirm: {
                showHl7UnavailablePopup = false
                // User stays on the screen — re-arm scanning so they can back out
                // or scan again (which will just re-trigger this popup).
                restartFlow()
            }
        )
        // Force the standard (light) palette so the dialog matches the rest of
        // the app instead of inheriting the camera screen's forced-dark colors.
        .environmentObject(appColors)
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
                isDispense: router.selectedPillScanningIsDispense ?? true,
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
