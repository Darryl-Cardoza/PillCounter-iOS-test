//
//  IdScanViewModel.swift
//  PillCounter
//
//  The feature's only @MainActor type. Owns the scan session — camera,
//  analyzer, sheet state, chip suggestions, frame-stall watchdog. Does NOT
//  own the name: the enrollment view model owns firstName/lastName, mirroring
//  Android's host-owns-name rule. See
//  plans/face-auth/ocr/19-08-2026-12-31-ocr-id-scan.md §4.1.
//

import AVFoundation
import Combine
import CoreVideo
import Foundation
import UIKit

enum ScanStatus {
    case scanning
    case paused
    case restarting
}

enum NameField {
    case first
    case last
}

@MainActor
final class IdScanViewModel: ObservableObject {

    @Published private(set) var status: ScanStatus = .scanning
    @Published var isSheetPresented = false
    @Published private(set) var suggestions: [String] = []
    @Published var activeField: NameField = .first
    /// Duplicate-name rejection, surfaced in the sheet now that the standalone
    /// name form is gone.
    @Published var nameError: String?

    let cameraService: IdScanCameraService

    private let analyzer: IdCardAnalyzer

    /// Name output — the host (FaceEnrollmentViewModel) owns the actual
    /// storage; these closures are how a fired scan result reaches it.
    private var setFirstName: ((String) -> Void)?
    private var setLastName: ((String) -> Void)?

    private var cameraSubscription: AnyCancellable?
    private var sessionLockSubscription: AnyCancellable?

    /// Last frame timestamp, used by the stall watchdog. Written on the main
    /// actor from the camera's frame callback (marshalled there below).
    private var lastFrameAt: Date?
    private var stallWatchdogTask: Task<Void, Never>?
    private var isSessionLocked = false

    private static let frameStallThreshold: TimeInterval = 4
    private static let frameStallCheckInterval: TimeInterval = 2

    init(
        cameraService: IdScanCameraService = IdScanCameraService(),
        analyzer: IdCardAnalyzer = IdCardAnalyzer()
    ) {
        self.cameraService = cameraService
        self.analyzer = analyzer

        // A nested ObservableObject doesn't propagate its own changes — the
        // preview would otherwise miss camera rotations/authorization state.
        cameraSubscription = cameraService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }

        // FaceEnrollmentView doesn't track session-lock state itself (the
        // lock overlay sits above the whole flow at a higher z-index and
        // needs no force-dismiss — see decision 8), so the scan step
        // observes it directly rather than waiting for a host push.
        sessionLockSubscription = FaceSessionManager.shared.$lockState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sessionLockChanged(isLocked: FaceSessionManager.shared.isLocked)
            }
    }

    /// Wires the scan result into the host's name fields. Called once by the
    /// view at appear time.
    func bind(setFirstName: @escaping (String) -> Void, setLastName: @escaping (String) -> Void) {
        self.setFirstName = setFirstName
        self.setLastName = setLastName
    }

    func start() {
        cameraService.onFrame = { [weak self] pixelBuffer in
            guard let self else { return }
            Task { @MainActor in
                self.lastFrameAt = Date()
            }
            self.analyzer.analyze(pixelBuffer: pixelBuffer) { [weak self] result in
                self?.handleScanResult(result)
            }
        }
        // Orientation must be set before the session starts — matches
        // CameraService's proven call order (configureInitialOrientation()
        // then start()), which avoids the connection picking up its default
        // angle before the real one is known.
        cameraService.configureInitialOrientation()
        cameraService.start()
        lastFrameAt = Date()
        startFrameStallWatchdog()
    }

    func stop() {
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
        cameraService.onFrame = nil
        cameraService.stop()
        analyzer.close()
    }

    func enterManually() {
        suggestions = []
        activeField = .first
        status = .paused
        cameraService.stop()
        analyzer.pause()
        isSheetPresented = true
    }

    /// Sheet dismissed via backdrop tap — the only iOS dismiss path, since the
    /// bottom sheet has no swipe gesture.
    func sheetDismissed() {
        isSheetPresented = false
        nameError = nil
        guard !isSessionLocked else { return }
        status = .scanning
        analyzer.resume()
        // The camera was stopped (and its orientation observer torn down)
        // while the sheet was up — the device may have rotated in the
        // meantime, so reseed before restarting, same as the initial start().
        cameraService.configureInitialOrientation()
        cameraService.start()
    }

    func sessionLockChanged(isLocked: Bool) {
        isSessionLocked = isLocked
        if isLocked {
            status = .paused
            cameraService.stop()
            analyzer.pause()
        } else if !isSheetPresented {
            status = .scanning
            analyzer.resume()
            cameraService.configureInitialOrientation()
            cameraService.start()
        }
    }

    // MARK: - Chip interaction

    /// Fills `activeField`, then advances first → last, or repeats on last —
    /// so the common repair (OCR paired the wrong two words) is exactly two
    /// taps. A tap always clears focus so the keyboard never appears.
    func chipTapped(_ word: String) {
        switch activeField {
        case .first:
            setFirstName?(word)
            activeField = .last
        case .last:
            setLastName?(word)
        }
    }

    // MARK: - Scan result handling

    private func handleScanResult(_ result: IdScanResult) {
        if let name = result.name {
            setFirstName?(name.firstName)
            setLastName?(name.lastName)
        }
        suggestions = result.suggestions
        activeField = .first
        status = .paused
        cameraService.stop()
        isSheetPresented = true
    }

    // MARK: - Frame-stall watchdog

    /// Independent of the analyzer's own watchdog: frames can flow while the
    /// analyzer's gate is latched (that's the analyzer's watchdog's job), and
    /// the gate can be free while no frames arrive at all — this is what
    /// catches the second case (e.g. the session lock's own capture session
    /// left ours in a bad state).
    private func startFrameStallWatchdog() {
        stallWatchdogTask?.cancel()
        stallWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.frameStallCheckInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.checkFrameStall()
            }
        }
    }

    private func checkFrameStall() {
        guard !isSheetPresented, !isSessionLocked else { return }
        guard let lastFrameAt else { return }
        guard Date().timeIntervalSince(lastFrameAt) >= Self.frameStallThreshold else { return }

        status = .restarting
        cameraService.stop()
        cameraService.start()
        self.lastFrameAt = Date()
    }
}
