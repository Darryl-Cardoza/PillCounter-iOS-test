//
//  CameraViewModel.swift
//  PillCounter
//
//  Optimized for performance, safety, and maintainability
//

import AVFoundation
import UIKit
import Foundation

final class CameraViewModel: NSObject, ObservableObject {

    // MARK: - PUBLISHED STATE
    @Published var scannedCode: String = ""
    @Published var codeType: String = ""
    @Published var isAuthorized: Bool = false
    @Published var error: String?
    @Published private(set) var currentCameraOrientation: UIDeviceOrientation = .portrait
    
    let decoder = BarcodeAndQRDecoder()


    // MARK: - SESSION CORE
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.viewmodel.session.queue")
    private var isConfigured = false
    private var hasScanned = false

    // MARK: - INPUT / OUTPUTS
    private var videoInput: AVCaptureDeviceInput?
    private let metadataOutput = AVCaptureMetadataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    // MARK: - PHOTO CAPTURE
    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    // MARK: - PREVIEW
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - INIT
    /// INITIALIZES VIEW MODEL AND CHECKS CAMERA PERMISSIONS
    override init() {
        super.init()
        checkPermissions()
    }

    // MARK: - PERMISSIONS
    /// CHECKS AND REQUESTS CAMERA AUTHORIZATION
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.configureSession() }
                }
            }
        default:
            isAuthorized = false
            error = "Camera access denied"
        }
    }

    // MARK: - SESSION CONFIGURATION
    /// CONFIGURES CAMERA INPUTS AND OUTPUTS ONCE
    private func configureSession() {
        sessionQueue.async {
            guard !self.isConfigured else { return }
            self.isConfigured = true

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // INPUT
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                DispatchQueue.main.async {
                    self.error = "Unable to access camera"
                }
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.videoInput = input

            // METADATA OUTPUT (BARCODES)
            if self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self,
                                                              queue: DispatchQueue.main)
                self.metadataOutput.metadataObjectTypes = [
                    .qr, .ean8, .ean13, .pdf417,
                    .code128, .code39, .code93,
                    .upce, .aztec, .dataMatrix,
                    .interleaved2of5, .itf14
                ]
            }

            // PHOTO OUTPUT
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()
        }
    }

    // MARK: - SESSION CONTROL
    /// STARTS CAMERA SESSION
    func startSession() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    /// STOPS CAMERA SESSION
    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// RETURNS ACTIVE CAPTURE SESSION
    func getSession() -> AVCaptureSession {
        session
    }

    // MARK: - ORIENTATION
    /// CONFIGURES INITIAL ORIENTATION FROM WINDOW SCENE
    func configureInitialOrientation() {
        currentCameraOrientation = initialOrientation()
        applyOrientation()
    }

    /// STARTS LISTENING TO DEVICE ORIENTATION CHANGES
    func startObservingOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    /// HANDLES DEVICE ORIENTATION CHANGE
    @objc private func handleOrientationChange() {
        let newOrientation = UIDevice.current.orientation
        guard newOrientation.isValidInterfaceOrientation,
              newOrientation != currentCameraOrientation else { return }

        currentCameraOrientation = newOrientation
        applyOrientation()
    }

    /// APPLIES ROTATION TO PREVIEW LAYER
    private func applyOrientation() {
        guard let connection = previewLayer?.connection else { return }
        let angle = currentCameraOrientation.videoRotationAngle
        guard connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// DETERMINES INITIAL ORIENTATION FROM UI SCENE
    private func initialOrientation() -> UIDeviceOrientation {
        guard let scene = UIApplication.shared.connectedScenes.first
                as? UIWindowScene else { return .portrait }

        switch scene.interfaceOrientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    // MARK: - PHOTO CAPTURE
    /// CAPTURES STILL IMAGE AND RETURNS UIIMAGE
    func captureImage(completion: @escaping (UIImage?) -> Void) {
        photoCaptureCompletion = completion

        let settings = AVCapturePhotoSettings()

        if let connection = photoOutput.connection(with: .video),
           let previewConnection = previewLayer?.connection {
            connection.videoRotationAngle = previewConnection.videoRotationAngle
        }

        sessionQueue.async {
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    func restartSession() {
        sessionQueue.async {
            self.hasScanned = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.session.startRunning()
        }
        DispatchQueue.main.async {
            self.scannedCode = ""
            self.codeType = ""
        }
    }

    /// Resets scan state without stopping the session — use after dismissing a sheet
    /// when the camera is already running and only the scan lock needs clearing.
    func resetScanState() {
        sessionQueue.async {
            self.hasScanned = false
        }
        DispatchQueue.main.async {
            self.scannedCode = ""
            self.codeType = ""
        }
    }
}

// MARK: - PHOTO DELEGATE
extension CameraViewModel: AVCapturePhotoCaptureDelegate {

    /// HANDLES PHOTO CAPTURE RESULT
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.photoCaptureCompletion?(nil)
            }
            return
        }

        DispatchQueue.main.async {
            self.photoCaptureCompletion?(image)
        }
    }
}

// MARK: - METADATA DELEGATE
extension CameraViewModel: AVCaptureMetadataOutputObjectsDelegate {

    /// HANDLES DETECTED BARCODE METADATA
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {

        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        
        hasScanned = true


        UINotificationFeedbackGenerator().notificationOccurred(.success)

//        let decodedGs1Value = decoder.decode(value)
//        let gtin = decodedGs1Value.gtin ?? ""
//        if gtin.isEmpty { return }
//    
        scannedCode = value
        codeType = object.type.rawValue
    }
}

// MARK: - ORIENTATION HELPER
extension UIDeviceOrientation {

    /// MAPS DEVICE ORIENTATION TO VIDEO ROTATION ANGLE
    var videoRotationAngle: CGFloat {
        switch self {
        case .landscapeLeft: return 0
        case .portrait: return 90
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }
}

