//
//  FaceTrackContinuityGate.swift
//  PillCounter
//
//  Watches the face's box, not the face, so a second person can't take over
//  halfway through enrollment.
//
//  Comparing embeddings across poses was measured on device (Android, same
//  YuNet + SFace models) and cannot do this: a genuine single-person
//  enrollment scored 0.140 while a real two-person swap scored 0.254 — the
//  distributions invert, so no threshold separates them. A swap instead has to
//  drop detection or jump the box, which is visible however weak the
//  recognizer is.
//
//  Driven by detection alone, never the quality gate — a blurry face is still
//  the same face, and failing quality must not look like a person swap. An
//  earlier iOS attempt at frame-to-frame IoU "broke on every legitimate head
//  turn"; that is what happens when the reference is only updated on frames
//  that pass quality, because a turn is exactly when quality fails most.
//
//  Port of Android's FaceTrackContinuityGate.
//

import CoreGraphics

final class FaceTrackContinuityGate {

    /// How much two consecutive boxes must overlap to be the same face.
    static let minTrackIoU: Float = 0.35

    /// Consecutive sampled frames with no face that are forgiven before the
    /// track is lost. ~450ms at the 150ms sampling interval.
    static let maxTrackGapFrames = 3

    /// True once an armed track has been lost. Latches — only `reset()` clears it.
    private(set) var isBroken = false

    private var gapFrames = 0
    private var isArmed = false
    private var lastBox: CGRect?

    /// Starts holding the track to account, at the straight-on capture.
    ///
    /// Keeps whatever box `observe` last saw rather than taking one: the frame
    /// that won the step was already observed, so re-detecting it would cost a
    /// second full detector pass for a box we already have.
    func arm() {
        isArmed = true
        isBroken = false
    }

    /// Follows the track through one sampled frame. `box` is nil when no
    /// single usable face was detected.
    func observe(_ box: CGRect?) {
        if isBroken { return }
        guard let box else {
            gapFrames += 1
            if gapFrames > Self.maxTrackGapFrames { loseTrack() }
            return
        }
        let previous = lastBox
        lastBox = box
        gapFrames = 0
        // A jump this large between frames 150ms apart is a different face,
        // not movement.
        if let previous, CGRectGeometry.iou(previous, box) < Self.minTrackIoU {
            loseTrack()
        }
    }

    /// Drops the last box without disarming, for a resume after the frame loop
    /// was stopped (the duplicate prompt). Nothing observed the track across
    /// that gap, so the next box starts a fresh comparison instead of being
    /// judged against a seconds-old one.
    func dropLastReference() {
        lastBox = nil
        gapFrames = 0
    }

    /// Clears everything, including `isBroken`. Called when the scan starts over.
    func reset() {
        isArmed = false
        isBroken = false
        lastBox = nil
        gapFrames = 0
    }

    private func loseTrack() {
        lastBox = nil
        gapFrames = 0
        // Before the straight-on capture there is nothing to protect — the
        // scan simply hasn't established whose face it is yet.
        if isArmed { isBroken = true }
    }
}
