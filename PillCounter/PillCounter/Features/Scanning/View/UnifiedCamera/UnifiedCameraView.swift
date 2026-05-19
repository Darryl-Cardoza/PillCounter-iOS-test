//
//  UnifiedCameraView.swift
//  PillCounter
//
//  Single full-screen camera experience: one shared AVCaptureSession powers
//  both barcode/QR scanning (AVCaptureMetadataOutput) and pill counting
//  (AVCaptureVideoDataOutput + CoreML via CameraService).
//
//  Architecture
//  ────────────
//  UnifiedCameraView                ← route owner, composes all layers
//    ├─ CameraView                  ← existing UIViewRepresentable (CameraService session)
//    ├─ DetectionOverlay            ← existing ML dot overlay (CameraService.detections)
//    ├─ TrayOverlay                 ← existing tray outline overlay
//    ├─ PillCountBadge              ← count number at bottom (new, minimal)
//    └─ UnifiedCameraState          ← enum driving which UI is active
//
//  State machine
//  ─────────────
//  .scanning      → camera live, barcode scanning active, pill count shown
//  .rxDetected    → barcode scanning stopped, RX bottom sheet shown,
//                   pill counting continues uninterrupted
//
//  Adding a new flow
//  ─────────────────
//  1. Add a case to UnifiedCameraState.
//  2. Branch on it inside the body ZStack or UnifiedCameraState switch.
//  3. Wire the trigger in handleScannedCode(_:).
//

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
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    // ── Navigation parameter ──────────────────────────────────────────────────
    let currentScanType: ScanType
    @State private var scanType: ScanType = .barcode

    // ── Camera: created eagerly so sheet/popup modifiers are always stable,
    //    but session.startRunning() is deferred until after navigation finishes.
    @StateObject private var cameraService = CameraService()

    // ── UI state ──────────────────────────────────────────────────────────────
    @State private var cameraState: UnifiedCameraState = .scanning
    @State private var scannedRawValue: String?
    @State private var capturedImage: UIImage?
    @State private var showManualEntryPopup: Bool = false
    @State private var scannedBottleContainerStatus: StockCountOptionContainerStatus = .sealed

    // ── Pill count panel (shown after barcode confirms drug) ──────────────────
    @State private var showPillCountPanel: Bool = false
    @State private var isAddDisabled: Bool = false
    @State private var showSuccessAnimation: Bool = false
    @State private var lastAddedCount: Int = 0
    @State private var showZeroCountPopup: Bool = false
    @State private var showNoteOption: Bool = false
    @State private var showConfirmCompletionPopup: Bool = false
    @State private var showDeleteAllTransactionDetailsPopup: Bool = false
    @State private var showStepCompletionPopup: Bool = false
    @State private var showCountMismatchPopup: Bool = false
    @State private var showTransactionDetailPopup: Bool = false
    @State private var selectedTransactionDetail: PillCountTransactionDetailsEntity?
    @State private var showTransactionHistory: Bool = true
    @State private var isPaused: Bool = false
    @State private var errorMessageOfNote: String?
    @State private var capturedVialImage: UIImage? = nil
    @State private var vialCapturedImagePath: String? = nil
    @State private var showCaptureFlash: Bool = false
    @State private var addNoteSettings: Bool = AppStorageManager.shared.isPillCountingEnabled
    @StateObject private var locationService = LocationService.shared

    @State private var scanTimeoutTask: Task<Void, Never>?
    private let scanTimeoutSeconds: UInt64 = 6
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLandscape) private var isLandscape

    var body: some View {
        rootWithAllPopups
    }

    // Split into layers so the type checker doesn't time out on a single long chain.
    private var rootWithAllPopups: some View {
        rootWithPillCountSheet
            .customPopup(isPresented: $showZeroCountPopup) { zeroCountPopupContent }
            .customPopup(isPresented: $showNoteOption) { showNoteOptionPopup }
            .customPopup(isPresented: $showConfirmCompletionPopup) { showConfirmCompletion }
            .customPopup(isPresented: $showDeleteAllTransactionDetailsPopup) { deleteAllTransactionDetailsPopup }
            .customPopup(isPresented: $showStepCompletionPopup) { showStepCompletion }
            .customPopup(isPresented: $showCountMismatchPopup) { countMismatchDialog }
            .customPopup(isPresented: $showTransactionDetailPopup) { showTransactionDetail }
            .overlay {
                if showSuccessAnimation {
                    SuccessAnimationView(count: lastAddedCount, color: appColors.secondary)
                        .allowsHitTesting(false)
                }
            }
    }

    private var pillCountSheetHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad
            ? UIScreen.main.bounds.height * 0.30
            : UIScreen.main.bounds.height * 0.42
    }

    private var rootWithPillCountSheet: some View {
        rootWithBarcodePopups
            .bottomSheet(
                isPresented: $showPillCountPanel,
                dismissOnBackgroundTap: false,
                showDim: false,
                portraitHeight: pillCountSheetHeight
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
//            .customPopup(isPresented: $pillScanViewModel.showScannedDrugInfoPopoup, dismissOnBackgroundTap: false) { scannedQrPopup }
            .customPopup(isPresented: $stockCountViewModel.showScannedNdcDoesNotMatch, dismissOnBackgroundTap: false) { ndcMismatchPopup }
    }

    // Extracted to help the type checker: layout + lifecycle observers
    private var rootContent: some View {
        cameraLayout
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
            .onChange(of: pillScanViewModel.currentControlledStep) { _, newStep in
                if showPillCountPanel {
                    SpeechManager.shared.speak(newStep.displayText)
                    pillScanViewModel.getAllTransactionDetailsOfTheCurrentTransaction()
                }
            }
            .onChange(of: scanType) { _, _ in handleStepVoice() }
            .onChange(of: pillScanViewModel.showScannedDrugInfoPopoup) { _, isShowing in
                if isShowing && scanType == .barcode{
                    pillScanViewModel.showToastMessage(text: L10n.BarcodeScan.qrScannedSuccessfully)
                    handleSubstitute()
                }
            }
    }

    // MARK: - Single camera layout — pill count panel slides up over it

    private var cameraLayout: some View {
        ZStack {
            // ── Camera + ML overlays (always present) ─────────────────────────
            if cameraService.isAuthorized {
                CameraView(session: cameraService.getSession(), cameraService: cameraService)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                CameraPermissionView()
            }

            DetectionOverlay(cameraService: cameraService)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            TrayOverlay(cameraService: cameraService)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // ── Pill count ring: visible only during barcode scan phase ────────
            if !showPillCountPanel {
                PillCountRingView(count: cameraService.stableCount)
            }


            // ── Loading spinner ───────────────────────────────────────────────
            if pillScanViewModel.isCheckingNdc || stockCountViewModel.isLoading {
                Color.black.opacity(0.5).ignoresSafeArea()
                PillCountingLoader()
            }

            // ── Inactivity pause overlay (full screen) ───────────────────────
            if cameraService.isPausedDueToInactivity {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            Text(L10n.PillCount.pausedDueToInactivity)
                                .foregroundStyle(appColors.text)
                            Button {
                                cameraService.resumeIfPaused()
                                cameraService.resetInactivityTimer()
                            } label: {
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

            // ── Header row (back button + instruction overlay) ────────────────
            VStack {
                HStack {
                    Button { router.navigateBack() } label: {
                        PillCountingIconView(
                            imageName: "back_icon",
                            size: 24,
                            padding: 12,
                            foregroundColor: appColors.primary,
                            backgroundColor: .clear,
                            scaleOnIpad: true
                        )
                    }
                    if !isLandscape{
                        Spacer()
                    }
                    if showPillCountPanel {
                        let isIpad = UIDevice.current.userInterfaceIdiom == .pad
                        if !controlledStepInstruction.isEmpty {
                            PillCountInstructionOverlay(text: controlledStepInstruction)
                                .padding(.leading, isLandscape ? (isIpad ? 220 : 100) : 0)
                        }
                    }
                    Spacer()
                    Color.clear.frame(width: 48, height: 48)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()
            }

            // ── Controlled step row: above sheet in portrait, bottom in landscape ─
            if showPillCountPanel,
               pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
                VStack(spacing: 0) {
                    if isLandscape {
                        Spacer()
                        HStack {
                            ControlledStepRow(
                                activeSteps: PillCountingStepResolver.getActiveSteps(
                                    txn: pillScanViewModel.currentTransaction
                                ),
                                currentStep: pillScanViewModel.currentControlledStep
                            )
                            .padding(.bottom, 8)
                            
                            Spacer().frame(width: 260)
                        }
                    } else {
                        Spacer()
                        ControlledStepRow(
                            activeSteps: PillCountingStepResolver.getActiveSteps(
                                txn: pillScanViewModel.currentTransaction
                            ),
                            currentStep: pillScanViewModel.currentControlledStep
                        )
                        Spacer().frame(height: pillCountSheetHeight)
                    }
                }
            }

            // ── Toast message ─────────────────────────────────────────────────
            if pillScanViewModel.showToast {
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
                    .padding(.bottom,  isLandscape ? 10 :  showPillCountPanel ? pillCountSheetHeight + 16 : 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: pillScanViewModel.showToast)
            }

        }
        .ignoresSafeArea()
        .onTapGesture {
            if cameraService.isPausedDueToInactivity {
                cameraService.resumeIfPaused()
                cameraService.cancelInactivityTimer()
            }
        }
    }

    private var controlledStepInstruction: String {
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
            onRedo: { handleVialRedo() },
            onCapture: { handleVialCapture() },
            onDone: { handleVialDone() }
        )
    }
}

// MARK: - Pill Count Ring
// Same ring + rolling-count animation as CountAddButtonView.
// isAnimating is driven by the same 0.5 s debounce used in BottomControlsViewBodyForPillScan.
// The Add button is simply not rendered.
private struct PillCountRingView: View {
    let count: Int
    @EnvironmentObject private var appColors: AppColors

    // ── Exact state from CountAddButtonView ───────────────────────────────────
    @State private var animationID = UUID()
    @State private var trimValue: CGFloat = 1.0
    @State private var displayedCount: Int = 0
    @State private var popScale: CGFloat = 1.0
    @State private var countTimer: Timer? = nil

    // ── isAnimating driven by same debounce as BottomControlsViewBodyForPillScan
    @State private var isAnimating: Bool = false
    @State private var stabilityWorkItem: DispatchWorkItem?

    private let size: CGFloat = 120

    var body: some View {
        VStack {
            Spacer()
            // ── Exact ZStack from CountAddButtonView (ring + count text) ──────
            ZStack {
                Circle()
                    .trim(from: 0, to: trimValue)
                    .stroke(
                        appColors.secondary,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: size, height: size)
                    .id(animationID)
                    .onAppear { updateAnimationState() }
                    .onChange(of: isAnimating) { _, _ in updateAnimationState() }

                Text("\(displayedCount)")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(appColors.text)
                    .scaleEffect(popScale)
            }
            .onChange(of: count) { _, newCount in
                scheduleAnimatingOff()
                if newCount == 0 { snapToZero() } else { animateCount(to: newCount) }
            }
            .onAppear {
                displayedCount = count
                scheduleAnimatingOff()
            }
            .padding(.bottom, 48)
        }
    }

    // ── Debounce: start animating on count change, stop after 0.5 s of silence ─
    private func scheduleAnimatingOff() {
        stabilityWorkItem?.cancel()
        if !isAnimating { isAnimating = true }
        let work = DispatchWorkItem { isAnimating = false }
        stabilityWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // ── Copied verbatim from CountAddButtonView ───────────────────────────────
    private func snapToZero() {
        countTimer?.invalidate()
        countTimer = nil
        displayedCount = 0
        popScale = 1.0
    }

    private func animateCount(to target: Int) {
        countTimer?.invalidate()
        countTimer = nil

        let start = displayedCount
        let delta = target - start
        guard delta != 0 else { return }

        let stepCount = abs(delta)
        let increment = delta > 0 ? 1 : -1
        let totalDuration: Double = min(Double(stepCount) * 0.04, 0.3)
        let interval: Double = totalDuration / Double(stepCount)
        var current = start

        countTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            current += increment
            displayedCount = current
            popScale = 1.15
            withAnimation(.spring(response: 0.12, dampingFraction: 0.45)) {
                popScale = 1.0
            }
            if current == target {
                t.invalidate()
                countTimer = nil
            }
        }
        RunLoop.main.add(countTimer!, forMode: .common)
    }

    private func updateAnimationState() {
        animationID = UUID()
        if isAnimating {
            trimValue = 0
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                trimValue = 1
            }
        } else {
            withAnimation(.linear(duration: 0.2)) {
                trimValue = 1
            }
        }
    }
}

// MARK: - Lifecycle
private extension UnifiedCameraView {

    func onAppear() {
        // Reset ALL viewModel popup flags so stale true values from a previous
        // visit never trigger popups immediately on re-entry.
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
        scanType = currentScanType

        cameraService.configureInitialOrientation()
        cameraService.startObservingOrientation()

        // Defer start() by one frame so the NavigationStack push animation
        // completes before AVCaptureSession begins — prevents the visual freeze.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            cameraService.start()
            cameraService.cancelInactivityTimer()
            cameraService.enableBarcodeScanning()
            startScanTimeout()
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
        pillScanViewModel.ndcNumber = ""
        pillScanViewModel.selectedTransaction = nil
        pillScanViewModel.targetCount = ["", "", "", ""]
        pillScanViewModel.drugNameMannuallyEntered = ""
        // Pill count panel cleanup (mirrors OPillCountView.onDisappear)
        if !pillScanViewModel.isNavigatingToDetailGrid {
            pillScanViewModel.currentTransaction = nil
            pillScanViewModel.currentTransactionTransactionDetails = nil
            pillScanViewModel.note = ""
            pillScanViewModel.currentControlledStep = .scan
            pillScanViewModel.currentControlledTargetCount = nil
        } else {
            pillScanViewModel.isNavigatingToDetailGrid = false
        }
        pillScanViewModel.reset()
    }
}

// MARK: - Event Handlers
private extension UnifiedCameraView {

    func handleStepVoice() {
        SpeechManager.shared.speak(scanType.instructionText)
    }

    func handleScannedCode(_ newValue: String) {
        guard !newValue.isEmpty,
              pillScanViewModel.isDrugFound == nil
        else { return }

        // Stop further barcode scanning immediately
        cameraService.disableBarcodeScanning()

        // Capture still frame from the running session
        if let snap = cameraService.captureSnapshot() { self.capturedImage = snap }
        scannedRawValue = newValue

        Task { @MainActor in
            guard pillScanViewModel.checkIsNdcMatch(rawValueFromBarcodeOrQr: newValue) else { return }

            if router.selectedPillScanningType == .FIXED
                && pillScanViewModel.selectedTransaction?.target_count == nil
            {
                switch currentScanType {
                case .rx_label:
                    if pillScanViewModel.matchesBarcodeFormat(newValue) {
                        cameraState = .rxDetected
                        pillScanViewModel.parseScanData(actualValue: newValue)
                    } else {
                        pillScanViewModel.isNdcEquivalent = false
                        pillScanViewModel.showNdcEquivalencePopup = true
                        pillScanViewModel.showToastMessage(text: "Invalid RX Barcode")
                    }
                case .barcode:
//                    pillScanViewModel.showScannedDrugInfoPopoup = true
                    handleSubstitute()
                case .stockCount:
                    await stockCountViewModel.getScannedDrugData(rawValue: newValue)
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
                pillScanViewModel.getControlledStep(
                    pillCountTxn: pillScanViewModel.currentTransaction
                )
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
        cameraService.resetBarcodeScanState()
        cameraService.enableBarcodeScanning()
        startScanTimeout()
        pillScanViewModel.isCheckingNdc = false
        pillScanViewModel.ndcComparisonResponse = nil
        pillScanViewModel.isNdcEquivalent = false
        pillScanViewModel.showNdcEquivalencePopup = false
        pillScanViewModel.ndcNumber = ""
        pillScanViewModel.drugName = ""
        pillScanViewModel.drugNameMannuallyEntered = ""
        stockCountViewModel.reset()
    }

    func handleAdd() {
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

    func handleVialCapture() {
        guard capturedVialImage == nil else {
            pillScanViewModel.showToastMessage(text: L10n.PillCount.imageAlreadyCaptured)
            return
        }
        guard let image = cameraService.captureSnapshot() else { return }
        cameraService.stop()
        let normalized = image.normalized()
        capturedVialImage = normalized
        showCaptureFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { showCaptureFlash = false }
        cameraService.stop()
        if let path = PhotoFileManager.shared.saveImage(normalized) {
            vialCapturedImagePath = path
        }
    }

    func handleVialRedo() {
        capturedVialImage = nil
        vialCapturedImagePath = nil
        cameraService.start()
        cameraService.rebindPreviewLayer()
        cameraService.resetInactivityTimer()
    }

    func handleVialDone() {
        let isPmsTxn = pillScanViewModel.currentTransaction?.is_from_pms ?? false
        let steps = PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction)
        let nextStep = pillScanViewModel.currentControlledStep.next(orderedSteps: steps)
        guard let imagePath = vialCapturedImagePath else { return }
        pillScanViewModel.addOrReplaceVialTransactionDetail(imagePath: imagePath)
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
        let value = (scannedRawValue?.isEmpty ?? true) ? pillScanViewModel.ndcNumber : scannedRawValue!
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

// MARK: - Popup Views
private extension UnifiedCameraView {

    var ndcEquivalencePopup: some View {
        ConfirmationDialogue(
            title: pillScanViewModel.isNdcEquivalent
                ? L10n.GenericEquivalent.doYouWantSubstitute
                : L10n.BarcodeScan.rescanRequired,
            message: pillScanViewModel.isNdcEquivalent
                ? L10n.GenericEquivalent.subtitle
                : L10n.BarcodeScan.ndcDoesNotMatch,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: pillScanViewModel.isNdcEquivalent
                ? L10n.BarcodeScan.substitute
                : L10n.BarcodeScan.rescan,
            showSingleConfirmButton: !pillScanViewModel.isNdcEquivalent,
            onCancel: {
                pillScanViewModel.showNdcEquivalencePopup = false
                restartFlow()
            },
            onConfirm: {
                if pillScanViewModel.isNdcEquivalent {
                    pillScanViewModel.showNdcEquivalencePopup = false
                    pillScanViewModel.showScannedDrugInfoPopoup = true
                } else {
                    restartFlow()
                }
            }
        )
    }

    var barcodeNotFoundPopup: some View {
        ConfirmationDialogue(
            title: L10n.BarcodeScan.drugNotFound,
            message: L10n.BarcodeScan.drugNotFoundMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.BarcodeScan.rescan,
            showSingleConfirmButton: true,
            onCancel: { restartFlow() },
            onConfirm: { restartFlow() }
        )
    }

    var stockCountDetailsPopup: some View {
        VStack(spacing: 23) {
            ScrollView {
                VStack {
                    Text(L10n.BarcodeScan.qrScannedSuccessfully)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(appColors.text)
                }
                .padding(.top)
                VStack(spacing: 16) {
                    KeyValueInfoCard(title: L10n.BarcodeScan.ndcNumber, value: stockCountViewModel.scannedDrugData?.ndc ?? "")
                    KeyValueInfoCard(title: L10n.BarcodeScan.drugName, value: stockCountViewModel.scannedDrugData?.drugName ?? "")
                    KeyValueInfoCard(title: L10n.BarcodeScan.quantity, value: String(stockCountViewModel.scannedDrugData?.quantity ?? 0))
                }
                VStack(alignment: .leading) {
                    Text(L10n.BarcodeScan.selectContainerStatus)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(appColors.text)
                }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                SegmentedPillSelector(options: [.sealed, .opened], selected: $scannedBottleContainerStatus) { option in
                    switch option {
                    case .sealed: return L10n.BarcodeScan.sealed
                    case .opened: return L10n.BarcodeScan.opened
                    }
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            EqualWidthHStackButtons(spacing: 30) {
                PillCountingButton(
                    iconName: nil, title: L10n.Common.cancel,
                    textColor: appColors.primary, backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 20, iconSize: 0,
                    action: { stockCountViewModel.showStockCountScannedDetails = false; restartFlow() }
                )
                PillCountingButton(
                    iconName: nil, title: L10n.Common.add,
                    textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 20, iconSize: 0,
                    action: {
                        stockCountViewModel.showStockCountScannedDetails = false
                        if pillScanViewModel.selectedTransaction?.is_from_pms == true,
                           let txn = pillScanViewModel.selectedTransaction {
                            pillScanViewModel.updatePmsTxnCount(
                                txn: txn,
                                containerStatus: scannedBottleContainerStatus,
                                scannedQty: Int(stockCountViewModel.scannedDrugData?.quantity ?? 0)
                            )
                        } else {
                            handleStockCountAdd()
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var scannedQrPopup: some View {
        VStack(spacing: 23) {
            ScrollView {
                VStack {
                    Text(L10n.BarcodeScan.qrScannedSuccessfully)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(appColors.text)
                }
                .padding(.top)
                VStack(spacing: 16) {
                    KeyValueInfoCard(title: L10n.BarcodeScan.ndcNumber, value: pillScanViewModel.scannedRxData?.ndcNo ?? "-")
                    KeyValueInfoCard(title: L10n.BarcodeScan.drugName, value: pillScanViewModel.scannedRxData?.drugName ?? "-")
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            EqualWidthHStackButtons(spacing: 30) {
                PillCountingButton(
                    iconName: nil, title: L10n.Common.cancel,
                    textColor: appColors.primary, backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 20, iconSize: 0,
                    action: { pillScanViewModel.showScannedDrugInfoPopoup = false; restartFlow() }
                )
                PillCountingButton(
                    iconName: nil, title: L10n.BarcodeScan.proceed,
                    textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 20, iconSize: 0,
                    action: { pillScanViewModel.showScannedDrugInfoPopoup = false; handleSubstitute() }
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    var ndcMismatchPopup: some View {
        ConfirmationDialogue(
            title: L10n.BarcodeScan.incorrectNdc,
            message: L10n.BarcodeScan.incorrectNdcMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.BarcodeScan.rescan,
            showSingleConfirmButton: true,
            onCancel: { restartFlow() },
            onConfirm: { restartFlow() }
        )
    }

    // MARK: - Pill Count Panel Popups

    var zeroCountPopupContent: some View {
        VStack(spacing: 25) {
            HStack {
                Text(L10n.PillCount.invalidCount)
                    .foregroundStyle(appColors.text)
                    .font(.headline)
                Spacer()
                Button { showZeroCountPopup = false } label: {
                    Image(systemName: "xmark")
                        .resizable().scaledToFit().frame(width: 16, height: 16)
                        .foregroundStyle(appColors.text)
                }
            }
            Text(L10n.PillCount.zeroPillsMessage)
                .foregroundStyle(appColors.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            PillCountingButton(
                iconName: nil, title: L10n.Common.ok,
                textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 30, horizontalPadding: 40, verticalPadding: 14, iconSize: 0,
                action: { showZeroCountPopup = false }
            )
        }
    }

    var showNoteOptionPopup: some View {
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
                    await MainActor.run { showConfirmCompletionPopup = true }
                }
            },
            secondaryTitle: pillScanViewModel.currentTransaction?.is_from_pms == false ? L10n.Common.skip : nil,
            secondaryAction: pillScanViewModel.currentTransaction?.is_from_pms == false ? {
                showNoteOption = false
                pillScanViewModel.note = ""
                Task(priority: .background) {
                    await MainActor.run { showConfirmCompletionPopup = true }
                }
            } : {},
            onClose: {
                showNoteOption = false
                showConfirmCompletionPopup = false
            }
        )
    }

    var showConfirmCompletion: some View {
        let isCompleted = pillScanViewModel.currentTransaction?.is_from_pms == true
            || router.selectedPillScanningType == .REGULAR
        let status = isCompleted ? "COMPLETED" : "PENDING"
        let message = isCompleted
            ? "Are you sure you want to mark this transaction as \(status)"
            : "Target not reached. This transaction will be marked as \(status)."

        return ConfirmationDialogue(
            title: L10n.PillCount.confirmCompletionTitle,
            message: message,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: {
                showNoteOption = false
                showConfirmCompletionPopup = false
            },
            onConfirm: {
                showNoteOption = false
                showConfirmCompletionPopup = false
                if pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
                    router.setRoot(to: .authentication(.login(.dashboard(.dashboardHome))))
                } else {
                    stockCountViewModel.updateCounts(
                        txnId: pillScanViewModel.currentTransaction?.txn_id,
                        bottleQty: nil,
                        looseQty: pillScanViewModel.addCurrentOpenPillCount
                    )
                    router.setRoot(
                        to: .authentication(.login(.dashboard(.pillCount(.stockCount(.stockCountBatchDetail)))))
                    )
                }
                if isCompleted {
                    Task(priority: .background) {
                        await userViewModel.completeTheSelectedTransaction(
                            txnId: pillScanViewModel.currentTransaction?.txn_id ?? 0,
                            countType: router.selectedPillScanningType ?? .FIXED
                        )
                    }
                }
            }
        )
    }

    var deleteAllTransactionDetailsPopup: some View {
        VStack(spacing: 20) {
            Text(L10n.PillCount.confirmDeletion)
                .foregroundStyle(appColors.text).font(.headline)
            Text(L10n.PillCount.deleteAllTransactionsMessage)
                .foregroundStyle(appColors.text).multilineTextAlignment(.center).padding(.horizontal)
            HStack {
                PillCountingButton(
                    iconName: nil, title: L10n.Common.no,
                    textColor: appColors.primary, backgroundColor: .clear, borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 18, iconSize: 0,
                    action: { showDeleteAllTransactionDetailsPopup = false }
                )
                PillCountingButton(
                    iconName: nil, title: L10n.Common.yes,
                    textColor: .white, backgroundColor: appColors.primary, borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 18, iconSize: 0,
                    action: {
                        showDeleteAllTransactionDetailsPopup = false
                        pillScanViewModel.deleteAllDetailsOfCurrentTransaction()
                    }
                )
            }
        }
    }

    var showStepCompletion: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.confirmStepCompletionTitle,
            message: L10n.PillCount.confirmStepCompletionMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: { showStepCompletionPopup = false },
            onConfirm: {
                showStepCompletionPopup = false
                if capturedVialImage != nil {
                    capturedVialImage = nil
                    vialCapturedImagePath = nil
                    cameraService.start()
                    cameraService.rebindPreviewLayer()
                    cameraService.resetInactivityTimer()
                }
                pillScanViewModel.handleStepCompletion()
            }
        )
    }

    var countMismatchDialog: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.countMismatchTitle,
            message: L10n.PillCount.countMismatchMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: { showCountMismatchPopup = false },
            onConfirm: {
                showNoteOption = true
                showCountMismatchPopup = false
            }
        )
    }

    var showTransactionDetail: some View {
        VStack(spacing: 35) {
            HStack {
                Text(String(format: L10n.PillCount.transactionDetail, selectedTransactionDetail?.txn_details_id ?? 0))
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
            HStack(spacing: 30) {
                if let image = selectedTransactionDetail?.image_path,
                   let loadedImage = PhotoFileManager.shared.loadImage(from: image) {
                    loadedImage.resizable().scaledToFill()
                        .frame(width: 140, height: 120).clipped().cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(appColors.text.opacity(0.5), lineWidth: 1)
                        .frame(width: 100, height: 80)
                }
                VStack(spacing: 10) {
                    Text(L10n.PillCount.header).foregroundStyle(appColors.primary)
                    CircleBadge(
                        size: 50, strokeWidth: 0, outerColor: .clear,
                        innerColor: appColors.secondary,
                        text: "\(selectedTransactionDetail?.pill_count ?? 0)",
                        textColor: .white,
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
            HStack {
                PillCountingButton(
                    iconName: nil, title: L10n.Common.delete,
                    textColor: appColors.primary, backgroundColor: .clear, borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 18, iconSize: 0,
                    action: {
                        showTransactionDetailPopup = false
                        pillScanViewModel.softDeleteCurrentTransactionSelectedTransactionDetail(
                            txnDetailId: selectedTransactionDetail?.txn_details_id ?? 0
                        )
                    }
                )
                PillCountingButton(
                    iconName: nil, title: L10n.Common.ok,
                    textColor: .white, backgroundColor: appColors.primary, borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 18, iconSize: 0,
                    action: { showTransactionDetailPopup = false }
                )
            }
        }
        .frame(width: 300)
    }
}
