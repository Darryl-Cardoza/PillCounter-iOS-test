//
//  CameraFocusController.swift
//  PillCounter
//
//  Focus-quality logic for CameraService: smooth-AF tradeoff, mid-adjustment
//  frame gating, and periodic barcode focus re-arm.
//

import AVFoundation

final class CameraFocusController {

    // MARK: - SMOOTH-AF

    /// Disables smooth-autofocus (defaults on, deliberately slows focus
    /// transitions) since a fast sharp lock matters more than smooth motion
    /// at the 15-30cm tray/barcode scanning distance. Must be called under
    /// the caller's own `device.lockForConfiguration()`.
    func applyFastFocusDefaults(on device: AVCaptureDevice) {
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = false
        }
    }

    // MARK: - FRAME STABILITY GATE

    /// True when the device is not currently hunting for focus or exposure.
    /// Cheap hardware-signal check (no per-pixel blur scoring) — call before
    /// feeding a frame to ML inference or using it for barcode decode, so a
    /// frame captured mid-adjustment is never treated as the frame to trust.
    func isFrameStable(for device: AVCaptureDevice) -> Bool {
        !device.isAdjustingFocus && !device.isAdjustingExposure
    }

    // MARK: - PERIODIC FOCUS RE-ARM (barcode scanning)

    private let reArmQueue: DispatchQueue
    private var reArmTimer: DispatchSourceTimer?
    private var restoreContinuousAFWorkItem: DispatchWorkItem?
    /// Number of active callers relying on the re-arm timer (barcode scanning,
    /// bottle rescan listening — either can start/stop independently of the
    /// other), so the timer only tears down once nobody needs it.
    private var reArmRefCount = 0

    /// - Parameter queue: the session queue the caller already serializes
    ///   device access on. Timer fires and touches `device` on this queue.
    init(reArmQueue: DispatchQueue) {
        self.reArmQueue = reArmQueue
    }

    /// Starts periodically re-centering the focus point of interest while
    /// barcode scanning is active. Continuous-AF alone can drift onto the
    /// background and stay there if the operator repositions the barcode —
    /// re-seeding the center point + a one-shot nudge every 1.5s pulls focus
    /// back onto whatever the operator is actually holding up. Ref-counted:
    /// a second caller starting re-arm while the first is still active does
    /// not reset the timer's phase.
    func startReArming(device: AVCaptureDevice) {
        reArmRefCount += 1
        guard reArmTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: reArmQueue)
        timer.schedule(deadline: .now() + 1.5, repeating: 1.5)
        timer.setEventHandler { [weak self, weak device] in
            guard let self, let device else { return }
            self.reArmCenterFocus(on: device)
        }
        timer.resume()
        reArmTimer = timer
    }

    /// Balances one `startReArming` call. Only tears the timer down once every
    /// caller has stopped, so one listener stopping never kills the timer a
    /// second, still-active listener relies on.
    func stopReArming() {
        reArmRefCount = max(0, reArmRefCount - 1)
        guard reArmRefCount == 0 else { return }
        tearDownReArmTimer()
    }

    /// Unconditionally stops re-arming regardless of how many callers are
    /// still "active" — for full session teardown (`stop()`), where nothing
    /// should keep running no matter what state the feature flags are in.
    func forceStopReArming() {
        reArmRefCount = 0
        tearDownReArmTimer()
    }

    private func tearDownReArmTimer() {
        reArmTimer?.cancel()
        reArmTimer = nil
        restoreContinuousAFWorkItem?.cancel()
        restoreContinuousAFWorkItem = nil
    }

    private func reArmCenterFocus(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            // One-shot nudge toward the center point, then fall back to
            // continuous so normal tracking resumes between re-arms.
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            // Intentionally silent — a failed re-arm must not break scanning.
        }

        // Restore continuous tracking shortly after the nudge so the device
        // isn't left in one-shot .autoFocus between timer firings. Tracked so
        // stopReArming() can cancel it if scanning stops within the 0.3s window.
        restoreContinuousAFWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak device] in
            guard let device, device.isFocusModeSupported(.continuousAutoFocus) else { return }
            do {
                try device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
            } catch {
                // Intentionally silent.
            }
        }
        restoreContinuousAFWorkItem = workItem
        reArmQueue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
}
