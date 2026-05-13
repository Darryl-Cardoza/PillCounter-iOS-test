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
    @EnvironmentObject private var stockCountVieModel: StockCountViewModel

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
    @State private var scannedBottleContainerStatus: StockCountOptionContainerStatus = .sealed
    
    let currentScanType: ScanType
    @State var scanType: ScanType = .barcode

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
                            
                            //Show BatchID at bottom
                            if currentScanType == .stockCount{
                                VStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        if let batchId = stockCountVieModel.currentBatch?.batch_id {
                                            PillCountInstructionOverlay(
                                                text: String("Batch \(batchId)")
                                            )
                                        }
                                    }
                                    .padding(.bottom, 30)
                                }
                            }
                        }
                    }
                },
                
                bottomContent: {
                    EmptyView()
                },
                headerActions: {
                    HStack {
                        Button {
                            router.navigateBack()
                        } label: {
                            PillCountingIconView(
                                 imageName: "back_icon",
                                 size: 24,
                                 padding: 12,
                                 foregroundColor: appColors.primary,
                                 backgroundColor: Color.clear,
                                 scaleOnIpad: true
                             )
                        }

                 
                        
                        Spacer()

                        PillCountInstructionOverlay(text: scanType.instructionText)

                        Spacer()

                        // Keeps overlay perfectly centered
                        Color.clear
                            .frame(width: 48, height: 48)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 65)
                },
                showBackButton: false,
                showHamburgerMenu: false,  // We have a manual entry button instead
                title: "",  // No title for scanner, usually cleaner
                allowKeyboardResize: true,
                
            )
            .ignoresSafeArea(.all)
            .onTapGesture {
                UIApplication.hideKeyboard()
            }
            
            //ShowLoader when loading api
            if pillScanViewModel.isCheckingNdc || stockCountVieModel.isLoading {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    PillCountingLoader()
                }
            }
            
        }
        .onAppear {
            // Reset ViewModel state so we are ready for a NEW transaction
            stockCountVieModel.reset()
            pillScanViewModel.resetScanningState()
            cameraManager.configureInitialOrientation()
            cameraManager.startObservingOrientation()
            // Reset local UI state
            showScannedData = false
            isFromScanning = false
            scannedData = nil
            scanType = currentScanType
            if scanType == .barcode {
                handleStepVoice()
            }
        }
        // MARK: - LIFECYCLE
        .task {
            cameraManager.startSession()
            startScanTimeout()
        }
        .onDisappear {
            pillScanViewModel.ndcNumber = ""
            pillScanViewModel.selectedTransaction = nil
            pillScanViewModel.targetCount = ["", "", "", ""]
            pillScanViewModel.drugNameMannuallyEntered = ""
            pillScanViewModel.reset()
            cameraManager.stopSession()
        }
        // MARK: - LOGIC HANDLERS
        .onChange(of: cameraManager.scannedCode) { _, newValue in
            handleScannedCode(newValue)
        }
        .onChange(of: pillScanViewModel.isDrugFound) { oldValue, newValue in
            handleDrugFoundState(newValue)
        }
        .onChange(of: pillScanViewModel.isNdcAdded){oldValue, newValue in
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
        .onChange(of: showMannualEntryPopup) { _, isShown in
            if isShown {
                scanTimeoutTask?.cancel()
            }
        }
        .onChange(of: scanType){_, newValue in
            handleStepVoice()
        }
        .customPopup(
            isPresented: $pillScanViewModel.showNdcEquivalencePopup,
            dismissOnBackgroundTap: false
        ) {
            showNdcEquivalencePopup
        }
        .customPopup(isPresented: $stockCountVieModel.barcodeNotFound){
            showBarcodeNotFoundPopup
        }
        .customPopup(
            isPresented: $stockCountVieModel.showStockCountScannedDetails,
            dismissOnBackgroundTap: false
        ) {
            stockCountScannedDetailsPopUp
        }
        .customPopup(isPresented: $pillScanViewModel.showRxFlowPopup, dismissOnBackgroundTap: false){
            rxScanSuccessPopup
        }
        .customPopup(isPresented: $pillScanViewModel.showScannedDrugInfoPopoup,  dismissOnBackgroundTap: false){
            scannedQrSuccessfullPopup
        }
        .customPopup(isPresented: $stockCountVieModel.showScannedNdcDoesNotMatch, dismissOnBackgroundTap: false){
            scannedNdcDoesNotMatchPmsBatchPopoup
        }
    }

    private func handleStepVoice() {
        SpeechManager.shared.speak(scanType.instructionText)
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


    
    private func handleStockCountAddAction() {
        Task {
            guard let batchId = stockCountVieModel.currentBatch?.batch_id else {
                return
            }
            await pillScanViewModel.createTxnForBatchFromScan(
                rawValueFromBarcodeOrQr: scannedData,
                ndc: stockCountVieModel.scannedDrugData?.ndc ?? "",
                drugName: stockCountVieModel.scannedDrugData?.drugName ?? "",
                quantity: Int32(Int(stockCountVieModel.scannedDrugData?.quantity ?? 0)),
                countType: .REGULAR,
                batchId: batchId,
                containerStatus: scannedBottleContainerStatus
            )
           stockCountVieModel.showStockCountScannedDetails  = false
        }
    }
}

// MARK: - LOGIC EXTENSIONS
extension QRBarcodeScannerView {

    private func handleScannedCode(_ newValue: String) {

        if !newValue.isEmpty {
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
                    
                    guard pillScanViewModel.checkIsNdcMatch(
                        rawValueFromBarcodeOrQr: newValue
                    ) else {
                        return
                    }
                    
                    if router.selectedPillScanningType == .FIXED
                         && pillScanViewModel.selectedTransaction?.target_count
                             == nil
                     {
                         switch currentScanType {
                         case .rx_label:
                             if pillScanViewModel.matchesBarcodeFormat(newValue) {
                                 pillScanViewModel.parseScanData(actualValue: newValue)
                             } else {
                                 pillScanViewModel.isNdcEquivalent = false
                                 pillScanViewModel.showNdcEquivalencePopup = true
                                 pillScanViewModel.showToastMessage(text: "Invalid RX Barcode")
                             }
                         case .barcode:
                             pillScanViewModel.showScannedDrugInfoPopoup = true
                         case .stockCount:
                             print("Stock Count Flow")
                             await stockCountVieModel.getScannedDrugData(rawValue: newValue)
                             return
                         }
                         
                     } else {
                         print("Regular Stock Count Flow")
                         await stockCountVieModel.getScannedDrugData(rawValue: newValue)
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
                    pillScanViewModel.showNdcEquivalencePopup = false
                    pillScanViewModel.showScannedDrugInfoPopoup = true
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
        stockCountVieModel.reset()
    }
}

// MARK: - POPUP
extension QRBarcodeScannerView {
   
   private var stockCountScannedDetailsPopUp: some View {
       VStack(spacing: 23) {
           ScrollView {
               VStack {
                   Text("QR Scanned Successfully")
                       .font(.system(size: 18, weight: .bold))
                       .foregroundColor(appColors.text)
                }
               .padding(.top)
               
               VStack(spacing: 16) {
                   
                   KeyValueInfoCard(
                       title: "NDC Number",
                       value: stockCountVieModel.scannedDrugData?.ndc ?? "" // here to come the ndc of the drug that i have scanned.
                   )
                   
                   KeyValueInfoCard(
                       title: "Drug Name",
                       value: stockCountVieModel.scannedDrugData?.drugName ?? ""
                   )
                   
                   KeyValueInfoCard(
                       title: "Quantity",
                       value: String(stockCountVieModel.scannedDrugData?.quantity ?? 0 )
                   )
               }
               
               VStack(alignment: .leading) {
                   Text("Select Container Status")
                       .font(.system(size: 16, weight: .regular))
                       .foregroundColor(appColors.text)
               }
               .padding(.vertical,3)
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
           }
           .scrollIndicators(.hidden)
           .fixedSize(horizontal: false, vertical: true ) //islandscape
           
           
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
                       stockCountVieModel.showStockCountScannedDetails = false
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
                       stockCountVieModel.showStockCountScannedDetails = false
                       // things to do on Add click button
                       // 1. create a batch
                       // 2. create a transaction for the current scanned bottle.
                       // 3. add the current transaction to the current batch that has been created or the one which are working on.
           
                       if pillScanViewModel.selectedTransaction?.is_from_pms == true{
                           if let txn = pillScanViewModel.selectedTransaction {
                               pillScanViewModel.updatePmsTxnCount(
                                   txn: txn,
                                   containerStatus: scannedBottleContainerStatus,
                                   scannedQty: Int(stockCountVieModel.scannedDrugData?.quantity ?? 0)
                               )
                           }
                       } else {
                           handleStockCountAddAction()
                       }
                   }
               )
           }
           .frame(maxWidth: .infinity, alignment: .center)
       }
   }
    
   private var rxScanSuccessPopup: some View {
       VStack(spacing: 23) {
           ScrollView {
               VStack {
                   Text("Label Scanned Successfully")
                       .font(.system(size: 18, weight: .bold))
                       .foregroundColor(appColors.text)
               }
               .padding(.top)
               VStack(spacing: 16) {
                   
                   KeyValueInfoCard(
                       title: "Rx Number",
                       value: pillScanViewModel.scannedRxData?.rxNo ?? "-"
                   )
                   KeyValueInfoCard(
                       title: "NDC Number",
                       value: pillScanViewModel.scannedRxData?.ndcNo ?? "-"
                   )
                   KeyValueInfoCard(
                       title: "Drug Name",
                       value: pillScanViewModel.scannedRxData?.drugName ?? "-"
                   )
                   KeyValueInfoCard(
                       title: "Quantity",
                       value: pillScanViewModel.scannedRxData?.qty ?? "-"
                   )
                   KeyValueInfoCard(
                       title: "Bucket",
                       value: pillScanViewModel.selectedBucket 
                   )
               }
           }
           .scrollIndicators(.hidden)
           .fixedSize(horizontal: false, vertical: true)
           // MARK: Buttons
           EqualWidthHStackButtons(spacing: 30) {
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
                       pillScanViewModel.showRxFlowPopup = false
                       restartFullScannerFlow()
                   }
               )
               PillCountingButton(
                   iconName: nil,
                   title: "PROCEED",
                   textColor: appColors.text,
                   backgroundColor: appColors.primary,
                   borderColor: .clear,
                   font: .system(size: 14, weight: .semibold),
                   cornerRadius: 30,
                   horizontalPadding: 32,
                   verticalPadding: 20,
                   iconSize: 0,
                   action: {
                       Task {
                           await pillScanViewModel.createTransactionFromRxScan()
                           scanType = .barcode
                           restartFullScannerFlow()
                       }
                   }
               )
           }
           .frame(maxWidth: .infinity)
       }
   }
   
   private var scannedQrSuccessfullPopup: some View {
       VStack(spacing: 23) {
           ScrollView {
               VStack {
                   Text("QR Scanned Successfully")
                       .font(.system(size: 18, weight: .bold))
                       .foregroundColor(appColors.text)
               }
               .padding(.top)
               VStack(spacing: 16) {
                   KeyValueInfoCard(
                       title: "NDC Number",
                       value: pillScanViewModel.scannedRxData?.ndcNo ?? "-"
                   )
                   
                   KeyValueInfoCard(
                       title: "Drug Name",
                       value: pillScanViewModel.scannedRxData?.drugName ?? "-"
                   )
               }
           }
           .scrollIndicators(.hidden)
           .fixedSize(horizontal: false, vertical: true)
           //  BUTTONS
           EqualWidthHStackButtons(spacing: 30) {
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
                       pillScanViewModel.showScannedDrugInfoPopoup = false
                       restartFullScannerFlow()
                   }
               )
               PillCountingButton(
                   iconName: nil,
                   title: "PROCEED",
                   textColor: Color.white,
                   backgroundColor: appColors.primary,
                   borderColor: .clear,
                   font: .system(size: 14, weight: .semibold),
                   cornerRadius: 30,
                   horizontalPadding: 32,
                   verticalPadding: 20,
                   iconSize: 0,
                   action: {
                       pillScanViewModel.showScannedDrugInfoPopoup = false
                       handleSubstitute()
                   }
               )
           }
           .frame(maxWidth: .infinity)
       }
   }
    
    private var showBarcodeNotFoundPopup : some View{
        ConfirmationDialogue(
            title: "Drug Not Found",
            message: "The scanned barcode is not recognized. Please try again.",
            cancelButtonText: "Cancel",
            confirmButtonText: "Rescan",
            showSingleConfirmButton: true,
            onCancel: {
                restartFullScannerFlow()
            },
            onConfirm: {
                restartFullScannerFlow()
            }
        )
    }

    private var scannedNdcDoesNotMatchPmsBatchPopoup : some View{
        ConfirmationDialogue(
            title: "Incorrect NDC",
            message: "You have scanned an incorrect NDC. This item does not match the PMS batch.",
            cancelButtonText: "Cancel",
            confirmButtonText: "Rescan",
            showSingleConfirmButton: true,
            onCancel: {
                restartFullScannerFlow()
            },
            onConfirm: {
                restartFullScannerFlow()
            }
        )
    }
}
