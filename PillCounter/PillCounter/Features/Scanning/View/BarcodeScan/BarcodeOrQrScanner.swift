//
//  BarcodeOrQrScanner.swift
//  PillCounter
//
//  Created by HC on 14/11/25.
//

import AVFoundation
import SwiftUI

// MARK: - CAMERA PREVIEW
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    @ObservedObject var cameraManager: CameraViewModel

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.session = session

        // Store preview layer reference
        cameraManager.previewLayer = view.previewLayer

        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // No-op to avoid re-rendering
    }

    class CameraPreviewView: UIView {
        var session: AVCaptureSession? {
            didSet {
                previewLayer.session = session
            }
        }

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            previewLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

// MARK: - MAIN VIEW
struct QRBarcodeScannerView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors
    @StateObject private var cameraManager = CameraViewModel()
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @EnvironmentObject private var userViewModel: UserViewModel

    @Environment(\.isLandscape) private var isLandscape
    @State private var stableIsLandscape: Bool = false
    @State private var landscapeDebounceTask: Task<Void, Never>? = nil

    // UI States
    @State private var showScannedData = false
    @State private var showMannualEntryPopup: Bool = false
    @State private var showPillTargetCountPopup: Bool = false
    @State private var isFromScanning: Bool = false
    @State private var scannedData: String?
    @State private var manualEntryError: String?
    @State private var tempCapturedImage: UIImage?

    private let labelWidth: CGFloat = 110

    @State private var scanTimeoutTask: Task<Void, Never>?
    private let scanTimeoutSeconds: UInt64 = 6

    @FocusState private var focusedField: InputField?

    @State private var showStockCountScannedDetails: Bool = false
    
    @State private var scannedBottleContainerStatus: StockCountOptionContainerStatus = .sealed

    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: {
                    GeometryReader { geo in
                        ZStack {
                            // 1. Camera Layer
                            // if permission granted show CameraPreview
                            if cameraManager.isAuthorized {
                                CameraPreview(
                                    session: cameraManager.getSession(),
                                    cameraManager: cameraManager
                                )
                                // We don't use ignoresSafeArea here because BaseView controls the frame.
                                // However, BaseView usually ignores safe area, so this will fill nicely.
                                .ignoresSafeArea()
                            } else {
                                // Fallback/Loading background
                                // Permission is not granted
                                Color.black.ignoresSafeArea()
                                CameraPermissionView()
                            }

                            // The SquareBreathing Box in camera view
                            if cameraManager.scannedCode.isEmpty && cameraManager.isAuthorized {
                                BarcodeScanBox()
                            }
                        }
                    }
                },

                bottomContent: {
//                    bottomContent
                    EmptyView()
                },
                headerActions: {
                    let instruction = ControlledStep.scan.displayText

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
                showHamburgerMenu: false,  // We have a manual entry button instead
                title: "",  // No title for scanner, usually cleaner
                allowKeyboardResize: true
            )
            .onTapGesture {
                UIApplication.hideKeyboard()
            }

            //ShowLoader when loading api
            if pillScanViewModel.isCheckingNdc {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    PillCountingLoader()
                }
            }

        }
        .onAppear {
            // Reset ViewModel state so we are ready for a NEW transaction
            pillScanViewModel.resetScanningState()
            cameraManager.configureInitialOrientation()
            cameraManager.startObservingOrientation()
            // Reset local UI state
            showScannedData = false
            isFromScanning = false
            scannedData = nil

            handleStepVoice(pillScanViewModel.currentControlledStep)
        }
        // MARK: - LIFECYCLE
        .task {
            cameraManager.startSession()
            startScanTimeout()
        }
        .onDisappear {
            //            cameraManager.stopSession()
            pillScanViewModel.ndcNumber = ""
            pillScanViewModel.selectedTransaction = nil
            pillScanViewModel.targetCount = ["", "", "", ""]
            pillScanViewModel.drugNameMannuallyEntered = ""
            cameraManager.stopSession()
        }
        // MARK: - LOGIC HANDLERS
        .onChange(of: cameraManager.scannedCode) { _, newValue in
//            handleScannedCode(newValue)
            showStockCountScannedDetails.toggle()
        }
        .onChange(of: pillScanViewModel.isDrugFound) { oldValue, newValue in
            handleDrugFoundState(newValue)
        }
        //        .onChange(
        //            of: pillScanViewModel.mannualDrugCreated,
        //            { oldValue, newValue in
        //                handleMannualEntryDrug(newValue)
        //            }
        //        )
        .onChange(of: showMannualEntryPopup) { _, isShown in
            if isShown {
                scanTimeoutTask?.cancel()
            }
        }
        .onChange(of: showPillTargetCountPopup) { _, newValue in
            if newValue == false {
                restartFullScannerFlow()
            }
        }
        .onChange(of: pillScanViewModel.shouldAutoProceedToCount) {
            _,
            shouldProceed in
            guard shouldProceed else { return }
            handleSubstitute()
            pillScanViewModel.shouldAutoProceedToCount = false
        }
        .customPopup(isPresented: $showPillTargetCountPopup) {
            mannulaEntryTargetCount
        }
        .customPopup(
            isPresented: $pillScanViewModel.showNdcEquivalencePopup,
            dismissOnBackgroundTap: false
        ) {
            showNdcEquivalencePopup
        }
        .customPopup(isPresented: $showStockCountScannedDetails) {
            stockCountScannedDetailsPopUp
        }
    }

    private func handleStepVoice(_ step: ControlledStep) {
        if step == .scan {
            SpeechManager.shared.speak(step.displayText)
        }
    }

    private var scanInstructionOverlay: some View {
        Text("Scan barcode / QR code")
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.5))
            .cornerRadius(24)
    }

    private func startScanTimeout() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task {
            try? await Task.sleep(
                nanoseconds: scanTimeoutSeconds * 1_000_000_000
            )
            // If still no scan → show manual entry
            if cameraManager.scannedCode.isEmpty
                && pillScanViewModel.isDrugFound == nil
            {
                await MainActor.run {
                    showMannualEntryPopup = true
                }
            }
        }
    }

    private var stockCountScannedDetailsPopUp: some View {
        VStack(spacing: 20) {

            VStack {
                Text("QR Scanned Successfully")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(appColors.text)
            }
            .padding(.top)
            
            VStack(spacing: 16) {
                
                KeyValueInfoCard(
                    title: "NDC Number",
                    value: "1234-3242-3455" // here to come the ndc of the drug that i have scanned.
                )
                
                KeyValueInfoCard(
                    title: "Drug Name",
                    value: "Levothyroxine Disul 50mg" // name of the drug
                )
                
                KeyValueInfoCard(
                    title: "Quantity",
                    value: "100" // quantity got from the barcode.
                )
            }
            
            VStack(alignment: .leading) {
                Text("Select Container Status")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(appColors.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            SegmentedPillSelector(
                options: [.sealed, .opened],
                selected: $scannedBottleContainerStatus
            ) { option in
                switch option {
                case .sealed: return "Sealed"
                case .opened: return "Opened"
                }
            }

            EqualWidthHStackButtons(spacing: 30){

                // DELETE
                PillCountingButton(
                    iconName: nil,
                    title: "CANCEL",
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        showStockCountScannedDetails = false
                        restartFullScannerFlow()
                    }
                )
                

                // ADD button
                PillCountingButton(
                    iconName: nil,
                    title: "ADD",
                    textColor: Color.white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        // some action to be performed
                        // navigate to the list screen of the current batch -- if the "SEALED" option has been selected.
                        // navigate to the Pill Count View for counting the pills -- if the "OPENED" has been selected.
                        // for this we would need to note the flow and clear it.
                        showStockCountScannedDetails = false
                        // things to do on Add click button
                        // 1. create a batch
                        // 2. create a transaction for the current scanned bottle.
                        // 3. add the current transaction to the current batch that has been created or the one which are working on.
                        handleStockCountAddAction()
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private func handleStockCountAddAction() {
        switch scannedBottleContainerStatus {
        case .sealed:
            Task {
                guard let batchId = pillScanViewModel.currentBatchId else {
                    return
                }

                await pillScanViewModel.createTxnForBatchFromScan(
                    rawValue: cameraManager.scannedCode,
                    countType: .REGULAR,
                    batchId: batchId
                )

                  router.navigate(
                      to: .authentication(
                          .login(
                              .dashboard(
                                  .pillCount(.stockCount(.stockCountBatchDetail))
                              )
                          )
                      )
                  )
              }
        case .opened:
            print("The bottle is open.")
        }
    }
}

// MARK: - LOGIC EXTENSIONS
extension QRBarcodeScannerView {

    private func handleScannedCode(_ newValue: String) {

        if !newValue.isEmpty {

            // Prevent duplicates
            if pillScanViewModel.isDrugFound != nil {
                return
            }

            if isFromScanning {
                return
            }

            cameraManager.captureImage { capturedImage in
                // Do not proceed when camera does not captured image
                guard let capturedImage else {
                    DispatchQueue.main.async {
                        cameraManager.restartSession()
                    }
                    return
                }

                self.tempCapturedImage = capturedImage

                // 3. Stop session after capture is done
                cameraManager.stopSession()

                // 4. Update UI
                showScannedData = true
                scannedData = newValue

                Task { @MainActor in
                    guard
                        pillScanViewModel.checkIsNdcMatch(
                            rawValueFromBarcodeOrQr: newValue
                        )
                    else { return }

                    if router.selectedPillScanningType == .FIXED
                        && pillScanViewModel.selectedTransaction?.target_count
                            == nil
                    {
                        showPillTargetCountPopup = true
                        isFromScanning = true
                    } else {
                        if pillScanViewModel.selectedTransaction?.is_from_pms
                            == true
                        {
                            pillScanViewModel.scnnedPmsPill(
                                rawValueFromBarcodeOrQr: newValue,
                                countType: router.selectedPillScanningType
                                    ?? .FIXED,
                                image: tempCapturedImage
                            )
                        } else {
                            await pillScanViewModel.scannedPill(
                                rawValueFromBarcodeOrQr: newValue,
                                countType: router.selectedPillScanningType
                                    ?? .FIXED,
                                image: tempCapturedImage
                            )
                        }
                    }
                }
            }
        }
    }

    private func handleMannualEntryDrug(_ newValue: Bool?) {
        switch newValue {
        case false:
            showMannualEntryPopup = false

        case true:
            router.navigate(
                to: .authentication(
                    .login(.dashboard(.pillCount(.pillCountView)))
                )
            )
            pillScanViewModel.isDrugFound = nil

        default:
            showMannualEntryPopup = false
        }
    }

    private func handleDrugFoundState(_ newValue: Bool?) {
        switch newValue {
        case false:
            showMannualEntryPopup = true
        case true:
            router.navigate(
                to: .authentication(
                    .login(.dashboard(.pillCount(.pillCountView)))
                )
            )
            pillScanViewModel.isDrugFound = nil
        default:
            showMannualEntryPopup = false
        }
    }
}

enum InputField: Hashable {
    case drugName
    case ndcNumber
}

// MARK: - UI COMPONENTS
extension QRBarcodeScannerView {

    private var portraitBottomContent: some View {

        VStack(spacing: 16) {
            // NDC Number row
            HStack(spacing: 12) {
                Text("NDC Number:")
                    .foregroundStyle(appColors.text)
                    .frame(width: labelWidth, alignment: .leading)

                PillCounterInputField(
                    imageName: nil,
                    placeholder: "",
                    disabled: false,
                    text: Binding(
                        get: { pillScanViewModel.ndcNumber },
                        set: { newValue in
                            pillScanViewModel.ndcNumber = formatNDC(newValue)
                        }
                    ),
                    keyboardType: .phonePad,
                    validation: .none,
                    maxLength: 13,
                    field: .ndcNumber,
                    focusedField: $focusedField
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 30)

            HStack(spacing: 12) {
                Text("Drug Name:")
                    .foregroundStyle(appColors.text)
                    .frame(width: labelWidth, alignment: .leading)

                PillCounterInputField(
                    imageName: nil,
                    placeholder: "",
                    disabled: false,
                    text: $pillScanViewModel.drugNameMannuallyEntered,
                    keyboardType: .default,
                    validation: .none,
                    field: .drugName,
                    focusedField: $focusedField
                )

                .frame(maxWidth: .infinity)
            }

            if let manualEntryError {
                Text(manualEntryError)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                PillCountingButton(
                    iconName: nil,
                    title: "CANCEL",
                    textColor: appColors.text,
                    backgroundColor: appColors.primaryBackground,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 18,
                    iconSize: 0,
                    action: {
                        showStockCountScannedDetails.toggle()
                        //                        router.navigateBack()
                        //                        pillScanViewModel.ndcNumber = ""
                        //                        pillScanViewModel.drugName = ""
                        //                        pillScanViewModel.drugNameMannuallyEntered = ""
                        //                        showMannualEntryPopup = false
                    }
                )

                PillCountingButton(
                    iconName: nil,
                    title: "OK",
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 12, weight: .regular),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 18,
                    iconSize: 0,
                    action: {
                        //Validate NDC
                        guard
                            !pillScanViewModel.ndcNumber
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        else {
                            manualEntryError = "NDC is required."
                            return
                        }

                        // Validate Drug Name
                        //                        guard !pillScanViewModel.drugNameMannuallyEntered
                        //                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        //                            .isEmpty else {
                        //                            manualEntryError = "Drug name is required."
                        //                            return
                        //                        }

                        if router.selectedPillScanningType == .FIXED {
                            if pillScanViewModel.selectedTransaction?
                                .is_from_pms == true
                            {
                                pillScanViewModel.manualEnterdControlledDrug(
                                    scannedNdc: pillScanViewModel.ndcNumber
                                )
                            } else {
                                showPillTargetCountPopup = true
                            }
                        } else {
                            Task {
                                if isFromScanning {
                                    isFromScanning = false
                                    await pillScanViewModel.scannedPill(
                                        rawValueFromBarcodeOrQr: scannedData
                                            ?? "",
                                        countType: router
                                            .selectedPillScanningType ?? .FIXED,
                                        image: tempCapturedImage
                                    )
                                } else {
                                    await pillScanViewModel
                                        .manualEntryDirectUpsert(
                                            ndc: pillScanViewModel.ndcNumber,
                                            drugName: pillScanViewModel
                                                .drugNameMannuallyEntered,
                                            countType: router
                                                .selectedPillScanningType
                                                ?? .FIXED
                                        )

                                }
                                showMannualEntryPopup = false
                            }
                        }
                    }
                )
            }
            .padding(.top, 8)
        }

        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .background(appColors.primaryBackground)
        .cornerRadius(24)
    }

    private var bottomContent: some View {
        Group {
            if stableIsLandscape {
                landscapeBottomContent
            } else {
                portraitBottomContent
            }
        }
    }

    private var landscapeBottomContent: some View {
        VStack(spacing: 14) {

            // NDC Number
            Text("NDC Number:")
                .foregroundStyle(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: Binding(
                    get: { pillScanViewModel.ndcNumber },
                    set: { newValue in
                        pillScanViewModel.ndcNumber = formatNDC(newValue)
                    }
                ),
                keyboardType: .phonePad,
                validation: .none,
                maxLength: 11,
                field: .ndcNumber,
                focusedField: $focusedField
            )

            //
            // Drug Name
            Text("Drug Name:")
                .foregroundStyle(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $pillScanViewModel.drugNameMannuallyEntered,
                keyboardType: .default,
                validation: .none,
                maxLength: nil,
                field: .drugName,
                focusedField: $focusedField
            )

            if let manualEntryError {
                Text(manualEntryError)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                PillCountingButton(
                    iconName: nil,
                    title: "CANCEL",
                    textColor: appColors.text,
                    backgroundColor: appColors.primaryBackground,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 18,
                    iconSize: 0,
                    action: {
                        showStockCountScannedDetails.toggle()
                        //                        pillScanViewModel.ndcNumber = ""
                        //                        pillScanViewModel.drugName = ""
                        //                        pillScanViewModel.drugNameMannuallyEntered = ""
                        //                        showMannualEntryPopup = false
                    }
                )

                PillCountingButton(
                    iconName: nil,
                    title: "OK",
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 12, weight: .regular),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 18,
                    iconSize: 0,
                    action: {
                        guard
                            !pillScanViewModel.ndcNumber
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        else {
                            manualEntryError = "NDC is required."
                            return
                        }

                        // Validate Drug Name
                        guard
                            !pillScanViewModel.drugNameMannuallyEntered
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        else {
                            manualEntryError = "Drug name is required."
                            return
                        }

                        if router.selectedPillScanningType == .FIXED {
                            if pillScanViewModel.selectedTransaction?
                                .is_from_pms == true
                            {
                                pillScanViewModel.manualEnterdControlledDrug(
                                    scannedNdc: pillScanViewModel.ndcNumber
                                )
                            } else {
                                showPillTargetCountPopup = true
                            }
                        } else {
                            Task {
                                if isFromScanning {
                                    isFromScanning = false
                                    await pillScanViewModel.scannedPill(
                                        rawValueFromBarcodeOrQr: scannedData
                                            ?? "",
                                        countType: router
                                            .selectedPillScanningType ?? .FIXED
                                    )
                                } else {
                                    await pillScanViewModel
                                        .manualEntryDirectUpsert(
                                            ndc: pillScanViewModel.ndcNumber,
                                            drugName: pillScanViewModel
                                                .drugNameMannuallyEntered,
                                            countType: router
                                                .selectedPillScanningType
                                                ?? .FIXED
                                        )
                                }
                                showMannualEntryPopup = false
                            }
                        }
                    }
                )
            }
            .padding(.top, 12)
            .padding(.top, 12)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .background(appColors.primaryBackground)
        .cornerRadius(24)
    }

    private var scannedCodeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(
                    systemName: cameraManager.codeType.contains("qr")
                        ? "qrcode" : "barcode"
                )
                .foregroundColor(.green)

                Text(
                    cameraManager.codeType.replacingOccurrences(
                        of: "org.iso.",
                        with: ""
                    ).uppercased()
                )
                .font(.caption)
                .foregroundColor(.green)

                Spacer()

                Button(action: {
                    cameraManager.startSession()
                    cameraManager.scannedCode = ""
                    cameraManager.codeType = ""
                    isFromScanning = false
                    tempCapturedImage = nil

                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                }
            }

            Text(cameraManager.scannedCode)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(3)

            Button(action: {
                UIPasteboard.general.string = cameraManager.scannedCode
            }) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding(.horizontal)
        .transition(.move(edge: .bottom))
        .animation(.spring(), value: showScannedData)
    }

    private var mannulaEntryTargetCount: some View {
        VStack(spacing: 25) {
            HStack {
                Text("PILLS REQUIRED")
                    .foregroundStyle(appColors.text)
                    .font(.headline)

                Spacer()

                Button {
                    showPillTargetCountPopup = false
                } label: {
                    Image(systemName: "xmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(appColors.text)
                }
            }

            BoxesInputField(otp: $pillScanViewModel.targetCount, reverse: true)
                .padding()
                .padding(.horizontal)

            HStack {
                PillCountingButton(
                    iconName: nil,
                    title: "CANCEL",
                    textColor: appColors.text,
                    backgroundColor: appColors.primaryBackground,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: {
                        pillScanViewModel.targetCount = ["", "", "", ""]
                        showMannualEntryPopup = false
                        showPillTargetCountPopup = false
                    }
                )

                PillCountingButton(
                    iconName: nil,
                    title: "OK",
                    textColor: Color.white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 12, weight: .regular),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: {
                        manualEntryError = nil

                        let joinedTargetCount = pillScanViewModel.targetCount
                            .joined()

                        guard let targetValue = Int(joinedTargetCount),
                            targetValue > 0
                        else {
                            return
                        }
                        Task {
                            if router.selectedPillScanningType == .FIXED {
                                if isFromScanning {
                                    isFromScanning = false
                                    await pillScanViewModel.scannedPill(
                                        rawValueFromBarcodeOrQr: scannedData
                                            ?? "",
                                        countType: router
                                            .selectedPillScanningType ?? .FIXED,
                                        image: tempCapturedImage
                                    )
                                } else {
                                    await pillScanViewModel
                                        .manualEntryDirectUpsert(
                                            ndc: pillScanViewModel.ndcNumber,
                                            drugName: pillScanViewModel
                                                .drugNameMannuallyEntered,
                                            countType: router
                                                .selectedPillScanningType
                                                ?? .FIXED
                                        )
                                }

                                showMannualEntryPopup = false
                                showPillTargetCountPopup = false

                            }

                            pillScanViewModel.markNdcVerified()
                        }
                    }
                )
            }
        }
        .frame(width: 300)
    }

    private var showNdcEquivalencePopup: some View {
        ConfirmationDialogue(
            title: pillScanViewModel.isNdcEquivalent
                ? NSLocalizedString("DO_YOU_WANT_SUBSTITUE", comment: "")
                : "Rescan Required",

            message: pillScanViewModel.isNdcEquivalent
                ? NSLocalizedString("GENERIC_EQUIVALENT_SUBTITLE", comment: "")
                : "The scanned ndc is does not match",

            cancelButtonText: "Cancel",

            confirmButtonText: pillScanViewModel.isNdcEquivalent
                ? "Substitute"
                : "Rescan",

            showSingleConfirmButton: !pillScanViewModel.isNdcEquivalent,
            onCancel: {
                pillScanViewModel.showNdcEquivalencePopup = false
                restartFullScannerFlow()
            },

            onConfirm: {
                if pillScanViewModel.isNdcEquivalent {
                    handleSubstitute()
                } else {
                    restartFullScannerFlow()
                }
            }
        )
    }

    private func handleSubstitute() {
        let valueToSend =
            (scannedData?.isEmpty ?? true)
            ? pillScanViewModel.ndcNumber : scannedData!

        Task { @MainActor in

            guard let txnId = pillScanViewModel.selectedTransaction?.txn_id
            else { return }

            let image = tempCapturedImage

            await pillScanViewModel.updateSubstitutedDrug(
                txnId: txnId,
                rawValue: valueToSend,
                countType: router.selectedPillScanningType ?? .FIXED,
                image: image
            )

            pillScanViewModel.markNdcVerified()
            pillScanViewModel.showNdcEquivalencePopup = false
        }
    }

    private func restartFullScannerFlow() {
        showScannedData = false
        showMannualEntryPopup = false
        showPillTargetCountPopup = false
        isFromScanning = false
        scannedData = nil
        cameraManager.scannedCode = ""
        cameraManager.codeType = ""
        cameraManager.restartSession()
        startScanTimeout()
        pillScanViewModel.isCheckingNdc = false
        pillScanViewModel.ndcComparisonResponse = nil
        pillScanViewModel.isNdcEquivalent = false
        pillScanViewModel.showNdcEquivalencePopup = false
        pillScanViewModel.ndcNumber = ""
        pillScanViewModel.drugName = ""
        pillScanViewModel.drugNameMannuallyEntered = ""
    }
}

@discardableResult
func DLOG(_ msg: String) -> Bool {
    print("[Scanner] \(msg)")
    return true
}
