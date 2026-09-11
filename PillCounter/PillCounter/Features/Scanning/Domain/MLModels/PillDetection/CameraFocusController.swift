//
//  CameraFocusController.swift
//  PillCounter
//
//  Focus-quality logic for CameraService: disables the smooth-AF tradeoff
//  that keeps the image soft, gates ML/barcode use of frames captured while
//  the device is still mid-adjustment, and periodically re-arms the focus
//  point during barcode scanning so AF can't stay drifted onto the
//  background. Kept in its own file (rather than folded into CameraService)
//  so this fix is easy to find on its own.
//

import AVFoundation

final class CameraFocusController {

    // MARK: - SMOOTH-AF

    /// Disables smooth-autofocus on the given device when supported. Must be
    /// called under the caller's own `device.lockForConfiguration()`.
    ///
    /// `isSmoothAutoFocusEnabled` defaults to true on `builtInWideAngleCamera`
    /// and deliberately slows focus transitions to avoid visible "focus
    /// breathing" in video — the wrong tradeoff when scanning trays/barcodes
    /// at 15-30cm, where a fast sharp lock matters more than smooth motion.
    /// Left on, the image stays continuously soft/blurry and barcode decode
    /// fails because the frame is never sharp enough to read.
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

    /// - Parameter queue: the session queue the caller already serializes
    ///   device access on. Timer fires and touches `device` on this queue.
    init(reArmQueue: DispatchQueue) {
        self.reArmQueue = reArmQueue
    }

    /// Starts periodically re-centering the focus point of interest while
    /// barcode scanning is active. Continuous-AF alone can drift onto the
    /// background and stay there if the operator repositions the barcode —
    /// re-seeding the center point + a one-shot nudge every 1.5s pulls focus
    /// back onto whatever the operator is actually holding up.
    func startReArming(device: AVCaptureDevice) {
        stopReArming()

        let timer = DispatchSource.makeTimerSource(queue: reArmQueue)
        timer.schedule(deadline: .now() + 1.5, repeating: 1.5)
        timer.setEventHandler { [weak self, weak device] in
            guard let self, let device else { return }
            self.reArmCenterFocus(on: device)
        }
        timer.resume()
        reArmTimer = timer
    }

    /// Stops the periodic re-arm. Call when barcode scanning stops or the
    /// session stops, so the timer doesn't outlive the capture session.
    func stopReArming() {
        reArmTimer?.cancel()
        reArmTimer = nil
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
        // isn't left in one-shot .autoFocus between timer firings.
        reArmQueue.asyncAfter(deadline: .now() + 0.3) { [weak device] in
            guard let device, device.isFocusModeSupported(.continuousAutoFocus) else { return }
            do {
                try device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
            } catch {
                // Intentionally silent.
            }
        }
    }
}
