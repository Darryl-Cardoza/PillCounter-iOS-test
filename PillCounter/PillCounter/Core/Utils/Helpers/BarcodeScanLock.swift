//
//  BarcodeScanLock.swift
//  PillCounter
//

import Foundation

/// Same-barcode re-scan gate shared by every camera barcode/QR listener
/// (primary NDC scan, bottle rescan, and any future scanner channel).
///
/// A scan event fires once per physical presentation of a barcode. The lock
/// stays held while that barcode is (mostly) visible in frame and releases
/// once `missThreshold` absent frames have been observed — the count is
/// CUMULATIVE, not consecutive. The decoder flickers present/absent almost
/// every other frame even while the barcode sits still in view, so a counter
/// that resets to 0 on any single "still visible" frame never reaches the
/// threshold and the lock gets stuck forever. Counting total misses since the
/// lock was set (a stray visible frame no longer wipes progress) is what
/// actually lets the lock release once the barcode is genuinely gone, while
/// still requiring more than one flickered "absent" reading to do it.
/// A DIFFERENT barcode appearing releases the lock immediately, no debounce.
///
/// `processFrame` MUST be called every metadata frame regardless of whether
/// the owner currently wants new scans to fire (e.g. while a previous scan is
/// still being processed). If frame delivery pauses while the barcode is
/// removed and re-presented, that removal is never observed and the lock
/// never releases — the same physical barcode then silently stops scanning
/// until forced open. Gate "should this fire" at the call site by ignoring
/// the return value when scanning is disabled, not by skipping the call.
final class BarcodeScanLock {
    private let missThreshold: Int
    private(set) var lockedValue: String?
    private var missFrames = 0

    init(missThreshold: Int = 2) {
        self.missThreshold = missThreshold
    }

    /// Feed this frame's visible barcode values and the frame's first decoded
    /// value (the candidate to lock onto if nothing is currently locked).
    /// Returns the value that should fire as a new scan event, or nil.
    func processFrame(visibleValues: [String], candidateValue: String?) -> String? {
        if let locked = lockedValue {
            if visibleValues.contains(locked) {
                // Barcode still visible this frame — do NOT reset missFrames.
                // The decoder flickers, so a lone "still visible" reading
                // between absent ones must not wipe out accumulated misses.
                return nil
            } else if visibleValues.isEmpty {
                // Barcode absent this frame — count toward the cumulative total.
                missFrames += 1
                if missFrames >= missThreshold {
                    lockedValue = nil
                    missFrames = 0
                }
                return nil
            } else {
                // A DIFFERENT barcode is now in frame — release lock immediately so
                // the new code fires right away. No debounce needed here: an actual
                // different decode can't be a flicker of the locked value.
                lockedValue = nil
                missFrames = 0
            }
        }

        guard lockedValue == nil, let value = candidateValue else { return nil }

        lockedValue = value
        missFrames = 0
        return value
    }

    /// Force-releases the lock. Use when starting a new scan session where
    /// re-scanning the exact same physical barcode is expected and desired —
    /// otherwise the lock from the previous scan silently blocks the identical
    /// barcode from firing again until it physically leaves and re-enters frame.
    func forceRelease() {
        lockedValue = nil
        missFrames = 0
    }
}
