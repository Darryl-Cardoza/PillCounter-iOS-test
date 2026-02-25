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


    var body: some View {
        ZStack {
            BaseView(
                topRatio: 0.7,
                topContent: {
                    GeometryReader { geo in

                    ZStack(alignment: .bottom) {
                        // 1. Camera Layer
                        // if permission granted show CameraPreview
                        if cameraManager.isAuthorized {
                            CameraPreview(
                                session: cameraManager.getSession(),
                                cameraManager: cameraManager
                            )
                            // We don't use ignoresSafeArea here because BaseView controls the frame.
                            // However, BaseView usually ignores safe area, so this will fill nicely.
                        } else {
                            // Fallback/Loading background
                            // Permission is not granted
                            Color.black
                        }
                        
                        // The SquareBreathing Box in camera view
                        if cameraManager.scannedCode.isEmpty {
                            BarcodeScanBox()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(alignment: .center) {
                                    BarcodeScanBox()
                                }
                        }

                        //ScanBarcode overlay box
                        VStack {
                            Spacer()
                            scanInstructionOverlay
                                .padding(.horizontal, 80)
                                .padding(.bottom, 20)
                            
                            // 2. Scanned Data Card (Overlay)

                        }
                    }
                }
                },
                
                bottomContent: {
                    // ManualNdc and drug name box
                    bottomContent
                }               ,
                headerActions: {},
                showBackButton: true,
                showHamburgerMenu: false,  // We have a manual entry button instead
                title: "" , // No title for scanner, usually cleaner
                allowKeyboardResize: true
            )
            .onTapGesture {
                UIApplication.hideKeyboard()
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 0)
        }
        .onAppear {
            // Reset ViewModel state so we are ready for a NEW transaction
            pillScanViewModel.resetScanningState()
            
            cameraManager.configureInitialOrientation()
            cameraManager.startObservingOrientation()

            // Reset local UI state\
            showScannedData = false
            isFromScanning = false
            scannedData = nil
        }
        // MARK: - LIFECYCLE
        .task {
            cameraManager.startSession()
            startScanTimeout()
        }
        .onDisappear {
            cameraManager.stopSession()
            pillScanViewModel.ndcNumber = ""
            pillScanViewModel.drugNameMannuallyEntered = ""
        }
        // MARK: - LOGIC HANDLERS
        .onChange(of: cameraManager.scannedCode) { _, newValue in
            handleScannedCode(newValue)
        }
        .onChange(of: pillScanViewModel.isDrugFound) { oldValue, newValue in
            handleDrugFoundState(newValue)
        }
        .onChange(
            of: pillScanViewModel.mannualDrugCreated,
            { oldValue, newValue in
                handleMannualEntryDrug(newValue)
            }
        )
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
        .customPopup(isPresented: $showPillTargetCountPopup) {
            mannulaEntryTargetCount
        }
        .customPopup(isPresented: $pillScanViewModel.showPmsNdcMismatchPopup) {
            showNdcMismatachDialog
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
            try? await Task.sleep(nanoseconds: scanTimeoutSeconds * 1_000_000_000)

            // If still no scan → show manual entry
            if cameraManager.scannedCode.isEmpty &&
               pillScanViewModel.isDrugFound == nil {
                await MainActor.run {
                    showMannualEntryPopup = true
                }
            }
        }
    }
    

    struct BarcodeScanBox: View {
        @State private var animate = false

        var body: some View {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AppColors.shared.primary,
                            AppColors.shared.secondary,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 180, height: 180)
                .scaleEffect(animate ? 1.05 : 0.95)
                .opacity(animate ? 1 : 0.6)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                    ) {
                        animate = true
                    }
                }
                .allowsHitTesting(false)
        }
    }
}

// MARK: - LOGIC EXTENSIONS
extension QRBarcodeScannerView {

    private func handleScannedCode(_ newValue: String) {
        if !newValue.isEmpty {
            // 1. Immediately pause session to freeze preview (optional visual effect)
            // cameraManager.stopSession() // You can stop here or let it run to capture

            // Prevent duplicates
            if pillScanViewModel.isDrugFound != nil { return }
            if isFromScanning { return }  // Simple flag check


            
            // 2. Capture the Photo
            cameraManager.captureImage { capturedImage in

                self.tempCapturedImage = capturedImage
                

                // 3. Stop session after capture is done
                cameraManager.stopSession()

                // 4. Update UI
                showScannedData = true
                scannedData = newValue
                
                Task { @MainActor in
                    pillScanViewModel.checkIsNdcMatch(rawValueFromBarcodeOrQr: newValue)

                    if router.selectedPillScanningType == .FIXED{
                        
                        showPillTargetCountPopup = true
                        isFromScanning = true
                        // Note: For fixed flow, we might hold onto capturedImage in a @State
                        // if you want to pass it later, but here we usually pass it immediately
                        // if we are creating the transaction now.
                        // Assuming Fixed flow creates transaction AFTER target input?
                        // If so, store 'capturedImage' in a State var.

                        // BUT, based on your previous code, 'scannedPill' is called in the ELSE block
                        // or passed later. Let's handle the REGULAR case first.
                    } else {
                        if(pillScanViewModel.selectedTransaction?.isComingFromPms == true){
                             pillScanViewModel.scnnedPmsPill(
                                rawValueFromBarcodeOrQr: newValue,
                                countType: router.selectedPillScanningType
                                ?? .FIXED,
                                image: tempCapturedImage
                            )
                        }else{
                            
                            // 5. Call ViewModel with Image
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
                    .login(.dashboard(.pillCount(.pillCountView)))))
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
                    .login(.dashboard(.pillCount(.pillCountView)))))
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
                        text: $pillScanViewModel.ndcNumber,
                        keyboardType: .phonePad,
                        validation: .none,
                        maxLength: 11,
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
                            router.navigateBack()
                            pillScanViewModel.ndcNumber = ""
                            pillScanViewModel.drugName = ""
                            pillScanViewModel.drugNameMannuallyEntered = ""
                            showMannualEntryPopup = false
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
                            guard !pillScanViewModel.ndcNumber
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty else {
                                manualEntryError = "NDC is required."
                                return
                            }
                            
                            // Validate Drug Name
                            guard !pillScanViewModel.drugNameMannuallyEntered
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty else {
                                manualEntryError = "Drug name is required."
                                return
                            }
                            
                            if router.selectedPillScanningType == .FIXED {
                                showPillTargetCountPopup = true
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
                                        await pillScanViewModel.manualEntryDirectUpsert(
                                            ndc: pillScanViewModel.ndcNumber,
                                            drugName: pillScanViewModel.drugNameMannuallyEntered,
                                            countType: router
                                                .selectedPillScanningType ?? .FIXED
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
                text: $pillScanViewModel.ndcNumber,
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
                        pillScanViewModel.ndcNumber = ""
                        pillScanViewModel.drugName = ""
                        pillScanViewModel.drugNameMannuallyEntered = ""
                        showMannualEntryPopup = false
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

                        guard !pillScanViewModel.ndcNumber
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty else {
                            manualEntryError = "NDC is required."
                            return
                        }

                        // Validate Drug Name
                        guard !pillScanViewModel.drugNameMannuallyEntered
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty else {
                            manualEntryError = "Drug name is required."
                            return
                        }

                        if router.selectedPillScanningType == .FIXED {
                            showPillTargetCountPopup = true
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
                                    await pillScanViewModel.manualEntryDirectUpsert(
                                        ndc: pillScanViewModel.ndcNumber,
                                        drugName: pillScanViewModel.drugNameMannuallyEntered,
                                        countType: router
                                            .selectedPillScanningType ?? .FIXED
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
                        of: "org.iso.", with: ""
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

    private var mannualEntryPopup: some View {
        VStack(spacing: 25) {

            // Header
            HStack {
                Text("ENTER PILL INFO MANUALLY")
                    .foregroundStyle(appColors.text)
                    .font(.headline)

                Spacer()

                Button {
                    showMannualEntryPopup = false
                } label: {
                    Image(systemName: "xmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(appColors.text)
                }
            }

            HStack {
                Text("Drug Name:")
                    .foregroundStyle(appColors.text)
                Spacer()
            }
            .padding(.horizontal)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $pillScanViewModel.drugNameMannuallyEntered,
                keyboardType: .default,
                validation: .none
            )
            .padding(.horizontal)

            HStack {
                Text("NDC Number:")
                    .foregroundStyle(appColors.text)
                Spacer()
            }
            .padding(.horizontal)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $pillScanViewModel.ndcNumber,
                keyboardType: .phonePad,
                validation: .phone,
                maxLength: 11
            )
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
                        pillScanViewModel.ndcNumber = ""
                        pillScanViewModel.drugName = ""
                        pillScanViewModel.drugNameMannuallyEntered = ""
                        showMannualEntryPopup = false
                        router.navigateBack()
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

                        if pillScanViewModel.ndcNumber.isEmpty {
                            return
                        }

                        if router.selectedPillScanningType == .FIXED {
                            showPillTargetCountPopup = true
                        } else {
                            Task {
                                if isFromScanning {
                                    isFromScanning = false
                                    await pillScanViewModel.scannedPill(
                                        rawValueFromBarcodeOrQr: scannedData
                                            ?? "",
                                        countType: router
                                            .selectedPillScanningType ?? .FIXED,
                                        
                                    )
                                } else {
                                    await pillScanViewModel.manuallyEnteredPill(
                                        ndc: pillScanViewModel.ndcNumber,
                                        countType: router
                                            .selectedPillScanningType ?? .FIXED
                                    )
                                }
                                showMannualEntryPopup = false
                            }
                        }
                    }
                )
            }
        }
        .frame(width: 300)
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
                               // Target count is 0 (e.g. "0000") or invalid
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
                                       await pillScanViewModel.manualEntryDirectUpsert(
                                        ndc: pillScanViewModel.ndcNumber,
                                        drugName: pillScanViewModel.drugNameMannuallyEntered,
                                        countType: router
                                            .selectedPillScanningType ?? .FIXED,
                                       )
                                   }
                                   showMannualEntryPopup = false
                                   showPillTargetCountPopup = false
                               }
                           }
                           //                        pillScanViewModel.targetCount = ["", "", "", ""]
                       }
                   )
               }
           }
           .frame(width: 300)
       }
    
    private var showNdcMismatachDialog: some View {
        ConfirmationDialogue(
            title: "Medication Mismatch",
            message: "The scanned NDC does not match the prescription received \nPlease verify the drug and scan again.",
            cancelButtonText: "Cancel",
            confirmButtonText: "Rescan",
            onCancel: {
                pillScanViewModel.showPmsNdcMismatchPopup = false
                router.navigateBack()
            },
            onConfirm: {
                pillScanViewModel.showPmsNdcMismatchPopup = false
                cameraManager.startSession()
            }
        )
    }
    
    private func restartFullScannerFlow() {
//        pillScanViewModel.resetScanningState()
        showScannedData = false
        showMannualEntryPopup = false
        showPillTargetCountPopup = false
        isFromScanning = false
        scannedData = nil
//        tempCapturedImage = nil
        cameraManager.restartSession()
        startScanTimeout()
    }
}


@discardableResult
func DLOG(_ msg: String) -> Bool {
    print("[Scanner] \(msg)")
    return true
}
    

