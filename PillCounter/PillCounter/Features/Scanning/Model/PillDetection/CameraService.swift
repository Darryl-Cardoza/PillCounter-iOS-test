//
//  CameraService.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import AVFoundation
import SwiftUI

final class CameraService: NSObject, ObservableObject {

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.queue")
    private let detector = PillDetectionService()

    @Published var stableCount: Int = 0
    @Published var detections: [DetectionResult] = []
    @Published var isAuthorized = false
    @Published var error: String?
    
    @Published private(set) var isPausedDueToInactivity = false

    private var didApplyInitialRotation = false

    var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var captureDevice: AVCaptureDevice?

    var lastPixelBuffer: CVPixelBuffer?
    
    private var inactivityTimer: DispatchSourceTimer?
    private let inactivityTimeout: TimeInterval = 25

    override init() {
        super.init()
        checkPermissions()
    }
    
    func resetInactivityTimer() {
        inactivityTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + inactivityTimeout)
        timer.setEventHandler { [weak self] in
            self?.pauseCameraForInactivity()
        }
        timer.resume()

        inactivityTimer = timer
    }
    
    private func pauseCameraForInactivity() {
        guard !isPausedDueToInactivity else { return }

        stop()
        isPausedDueToInactivity = true
    }
    
    func resumeIfPaused() {
        guard isPausedDueToInactivity else { return }

        start()
        isPausedDueToInactivity = false
        resetInactivityTimer()
    }



    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.configure() }
                }
            }
        default:
            isAuthorized = false
            error = "Camera access denied"
        }
    }

    // MARK: - Camera Configuration
    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.session.sessionPreset = .photo  // Changed to photo for better quality/aspect ratio

            guard
                let videoDevice = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: .back),
                let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
            else {
                DispatchQueue.main.async { self.error = "Cannot access camera" }
                return
            }

            if self.session.canAddInput(videoInput) {
                self.session.addInput(videoInput)
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(
                self, queue: sessionQueue
            )

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]

            videoOutput.alwaysDiscardsLateVideoFrames = true

            if self.session.canAddOutput(videoOutput) {
                self.session.addOutput(videoOutput)
            }

            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
        resetInactivityTimer()
    }

    func stop() {
        inactivityTimer?.cancel()
        inactivityTimer = nil
        
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func getSession() -> AVCaptureSession {
        return session
    }

    // MARK: - Orientation Fix
    func updateOrientation(_ orientation: UIDeviceOrientation) {
        // Ensure we are on main thread to touch UI layers
        DispatchQueue.main.async {
            guard let connection = self.previewLayer?.connection,
                connection.isVideoOrientationSupported
            else { return }

            let videoOrientation: AVCaptureVideoOrientation
            switch orientation {
            case .portrait: videoOrientation = .portrait
            case .landscapeLeft: videoOrientation = .landscapeRight  // Cameras are often mirrored
            case .landscapeRight: videoOrientation = .landscapeLeft
            case .portraitUpsideDown: videoOrientation = .portraitUpsideDown
            default: videoOrientation = .portrait
            }

            connection.videoOrientation = videoOrientation

            // Force the layer to match the bounds immediately
            if let superlayer = self.previewLayer?.superlayer {
                self.previewLayer?.frame = superlayer.bounds
            }
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        self.lastPixelBuffer = pixelBuffer

        // Detection pipeline
        detector.detect(pixelBuffer: pixelBuffer) {
            [weak self] detections, stabilizedCount in
            DispatchQueue.main.async {
                self?.detections = detections
                self?.stableCount = stabilizedCount
            }
        }
    }
}

extension CameraService {

    // 1. CALL THIS FUNCTION FROM YOUR "ADD" BUTTON
    func captureSnapshotWithOverlays() -> UIImage? {
        // This variable needs to be added to your class (see Step 2 below)
        guard let pixelBuffer = self.lastPixelBuffer else {
            print("❌ No frame to capture")
            return nil
        }

        // Convert PixelBuffer to CIImage then CGImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        else { return nil }

        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let size = CGSize(width: width, height: height)

        // Begin Image Context to draw boxes
        let renderer = UIGraphicsImageRenderer(size: size)

        let combinedImage = renderer.image { ctx in
            let cgContext = ctx.cgContext

            // A. Draw the raw camera image first
            // Note: Coordinate system in CoreGraphics is often flipped compared to UIKit
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: height)
            cgContext.scaleBy(x: 1.0, y: -1.0)
            cgContext.draw(cgImage, in: CGRect(origin: .zero, size: size))
            cgContext.restoreGState()

            // B. Setup Drawing Style (Yellow Lines like your View)
            cgContext.setStrokeColor(UIColor.yellow.cgColor)
            cgContext.setLineWidth(5.0)  // Thicker line for high-res photo

            // C. Draw Detections
            for (index, detection) in detections.enumerated() {
                // The detection.rect is already relative to the frame size (pixel buffer size)
                // So we can use it directly!
                let rect = detection.rect

                // Draw Box
                cgContext.addRect(rect)
                cgContext.strokePath()

                // Draw Number Badge (Optional, slightly complex in CoreGraphics)
                drawBadge(context: cgContext, index: index, rect: rect)
            }
        }

        // D. Fix Orientation
        // The raw buffer is usually Landscape (rotated 90deg relative to Portrait phone).
        // We wrap it in a UIImage with .right orientation to make it upright.
        return UIImage(
            cgImage: combinedImage.cgImage!, scale: 1.0, orientation: .right)
    }

    // Helper to draw the circle number
    private func drawBadge(context: CGContext, index: Int, rect: CGRect) {
        let badgeSize: CGFloat = 40
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let badgeRect = CGRect(
            x: center.x - badgeSize / 2, y: center.y - badgeSize / 2,
            width: badgeSize, height: badgeSize)

        // Fill Black Circle
        context.setFillColor(UIColor.black.withAlphaComponent(0.8).cgColor)
        context.fillEllipse(in: badgeRect)

        // Stroke Yellow Circle
        context.setStrokeColor(UIColor.yellow.cgColor)
        context.setLineWidth(3.0)
        context.strokeEllipse(in: badgeRect)

        // Draw Text (Simple version)
        // Note: Drawing text in CoreGraphics is verbose.
        // For simplicity in this snippet, we might skip text or use a basic UIString drawer if imported.
    }
}
