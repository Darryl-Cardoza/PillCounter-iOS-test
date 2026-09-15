//
//  PillTracker.swift
//  PillCounter
//
//  Port of the Android PillTracker (deploy-contract hysteresis tracker).
//

import CoreGraphics
import Foundation

/// Per-track state machine over the post-NMS pill detections: a track confirms
/// (and counts) after `enterFrames` consecutive hits at `enterScore`, coasts
/// through up to `exitUnmatchedFrames` misses (still returned, so a one-frame
/// drop can't move the count) while matching at `keepScore`, then exits — one
/// pill per track, so a leftover detection or unmatched track that lands on a
/// pill another track already claimed this frame is dropped rather than
/// spawning/coasting a duplicate (NMS alone lets 0.3-0.5 IoU or partial boxes
/// through, and a box that jumps frames would otherwise get a second track
/// while its old one coasts). Before association each frame, tracks are
/// shifted by the camera motion — the passed-in `CameraMotionEstimator`
/// estimate validated against detections, or a median displacement vote when
/// unavailable — so a hand-held pan doesn't miss every track and spawn a
/// duplicate for every detection. Not thread-safe; drive it from one queue.
final class PillTracker {

    static let trackIoU: Float = 0.30
    static let enterScore: Float = 0.50
    static let enterFrames = 2
    static let keepScore: Float = 0.35
    static let exitUnmatchedFrames = 3
    /// Two boxes are the same pill when the smaller is mostly inside the larger
    /// (a partial box on a whole pill). Distinct touching pills overlap far less.
    static let duplicateContainment: Float = 0.70
    /// Fallback shift vote: a detection votes with its displacement from the
    /// nearest track within this many median pill sides; at least
    /// `minShiftVotes` votes are needed.
    static let shiftSearchRadiusPills: CGFloat = 2
    static let minShiftVotes = 3

    private final class Track {
        var rect: CGRect
        var confidence: Float
        var hitStreak: Int
        var missedFrames = 0
        var confirmed: Bool

        init(rect: CGRect, confidence: Float, hitStreak: Int, confirmed: Bool) {
            self.rect = rect
            self.confidence = confidence
            self.hitStreak = hitStreak
            self.confirmed = confirmed
        }
    }

    private var tracks: [Track] = []
    private var lastFrameSize: CGSize = .zero

    /// Advances every track by one frame and returns the confirmed ones as
    /// detections in the same (frame-pixel) coordinate space the input used.
    ///
    /// - Parameter cameraShift: how far the scene moved since the last frame, in
    ///   frame pixels, from image registration. Nil falls back to a vote over
    ///   the detections.
    func update(_ detections: [DetectionResult], cameraShift: CGVector? = nil) -> [DetectionResult] {
        if let size = detections.first?.originalFrameSize { lastFrameSize = size }

        // Snapshot the existing tracks: one created this frame must not be
        // available for association until the next frame.
        let existingCount = tracks.count
        if let shift = resolveShift(detections, measured: cameraShift) {
            for t in tracks { t.rect = t.rect.offsetBy(dx: shift.dx, dy: shift.dy) }
        }

        var matched = [Bool](repeating: false, count: existingCount)
        var spawned: [Track] = []
        var leftovers: [DetectionResult] = []

        for det in detections.sorted(by: { $0.confidence > $1.confidence }) {
            if det.confidence < Self.keepScore { continue }

            var bestIdx = -1
            var bestIou: Float = -1
            for i in 0..<existingCount where !matched[i] {
                let overlap = CGRectGeometry.iou(det.rect, tracks[i].rect)
                if overlap >= Self.trackIoU && overlap > bestIou {
                    bestIou = overlap
                    bestIdx = i
                }
            }

            if bestIdx >= 0 {
                matched[bestIdx] = true
                let track = tracks[bestIdx]
                if track.confirmed {
                    // Confirmed: any match at or above keep score refreshes it.
                    track.rect = det.rect
                    track.confidence = det.confidence
                    track.missedFrames = 0
                } else if det.confidence >= Self.enterScore {
                    // Candidate: only a match at or above enter score extends the streak.
                    track.hitStreak += 1
                    track.rect = det.rect
                    track.confidence = det.confidence
                    track.missedFrames = 0
                    if track.hitStreak >= Self.enterFrames { track.confirmed = true }
                } else {
                    // Candidate matched below enter score: the streak breaks and the
                    // track ages toward exit rather than living on indefinitely.
                    track.hitStreak = 0
                    track.missedFrames += 1
                }
            } else if det.confidence >= Self.enterScore {
                // A track only ever starts at enter score — a borderline detection
                // that matches nothing is not evidence of a new pill.
                leftovers.append(det)
            }
        }

        // Leftovers are in confidence order. One starts a track only if it lies
        // on no pill already accounted for this frame — neither a track matched
        // above nor a track spawned from a stronger leftover.
        for det in leftovers {
            let onTrackedPill = (0..<existingCount).contains { matched[$0] && Self.samePill(det.rect, tracks[$0].rect) }
                || spawned.contains { Self.samePill(det.rect, $0.rect) }
            if onTrackedPill { continue }
            spawned.append(Track(rect: det.rect,
                                 confidence: det.confidence,
                                 hitStreak: 1,
                                 confirmed: Self.enterFrames <= 1))
        }

        for i in 0..<existingCount where !matched[i] {
            let track = tracks[i]
            // An unmatched track lying on a pill that a matched track now covers is
            // a ghost — the pill's box moved and re-associated, or a duplicate box
            // vanished. Retire it now instead of counting it while it coasts.
            let ghost = (0..<existingCount).contains { matched[$0] && Self.samePill(track.rect, tracks[$0].rect) }
            track.missedFrames = ghost ? Self.exitUnmatchedFrames : track.missedFrames + 1
            // "2 consecutive frames" means consecutive — a miss breaks the streak.
            if !track.confirmed { track.hitStreak = 0 }
        }
        tracks.removeAll { $0.missedFrames >= Self.exitUnmatchedFrames }
        tracks.append(contentsOf: spawned)

        let frameSize = lastFrameSize
        return tracks
            .filter { $0.confirmed }
            .map { DetectionResult(rect: $0.rect, confidence: $0.confidence, originalFrameSize: frameSize,
                                    isCoasting: $0.missedFrames > 0) }
    }

    /// Drops all tracks so the next frame starts confirmation from scratch.
    func reset() {
        tracks.removeAll()
    }

    // MARK: - Camera motion

    /// The shift applied to every track before association.
    ///
    /// A measured shift is validated against the data: of {none, ±dx ±dy} the
    /// candidate that lets the most detections find a track wins, so a sign or
    /// axis convention in the registration can never make association worse
    /// than doing nothing. Without a measurement, the detections vote.
    private func resolveShift(_ detections: [DetectionResult], measured: CGVector?) -> CGVector? {
        guard !tracks.isEmpty else { return nil }
        if let m = measured {
            if abs(m.dx) + abs(m.dy) < 1 { return nil }
            let candidates = [
                CGVector(dx: 0, dy: 0),
                m,
                CGVector(dx: -m.dx, dy: -m.dy),
                CGVector(dx: m.dx, dy: -m.dy),
                CGVector(dx: -m.dx, dy: m.dy)
            ]
            var best = CGVector(dx: 0, dy: 0)
            var bestMatches = -1
            for c in candidates {
                let n = matchCount(detections, shift: c)
                if n > bestMatches {
                    bestMatches = n
                    best = c
                }
            }
            return (best.dx == 0 && best.dy == 0) ? nil : best
        }
        return shiftFromDetections(detections)
    }

    /// Detections that would find a track at the association IoU if every track
    /// were moved by `shift`.
    private func matchCount(_ detections: [DetectionResult], shift: CGVector) -> Int {
        var n = 0
        for det in detections where det.confidence >= Self.keepScore {
            let r = det.rect.offsetBy(dx: -shift.dx, dy: -shift.dy)
            if tracks.contains(where: { CGRectGeometry.iou(r, $0.rect) >= Self.trackIoU }) { n += 1 }
        }
        return n
    }

    /// Fallback camera-motion estimate: median displacement from each detection
    /// to its nearest existing track, or nil when too few detections have a
    /// track near enough to vote. Reliable while the shift stays under half the
    /// pill spacing; beyond that only image registration can tell.
    private func shiftFromDetections(_ detections: [DetectionResult]) -> CGVector? {
        guard detections.count >= Self.minShiftVotes else { return nil }
        let radius = Self.shiftSearchRadiusPills
            * detections.map { ($0.rect.width * $0.rect.height).squareRoot() }.median()
        var dxs: [CGFloat] = []
        var dys: [CGFloat] = []
        for det in detections where det.confidence >= Self.keepScore {
            let c = det.center
            var nearest: Track?
            var nearestDist = CGFloat.greatestFiniteMagnitude
            for t in tracks {
                let d = hypot(t.rect.midX - c.x, t.rect.midY - c.y)
                if d < nearestDist {
                    nearestDist = d
                    nearest = t
                }
            }
            guard let n = nearest, nearestDist <= radius else { continue }
            dxs.append(c.x - n.rect.midX)
            dys.append(c.y - n.rect.midY)
        }
        guard dxs.count >= Self.minShiftVotes else { return nil }
        return CGVector(dx: dxs.median(), dy: dys.median())
    }

    // MARK: - Geometry

    /// Two boxes describe the same pill when they overlap at the association
    /// threshold, or when the smaller box is mostly inside the larger one.
    private static func samePill(_ a: CGRect, _ b: CGRect) -> Bool {
        let inter = CGRectGeometry.intersectionArea(a, b)
        if inter <= 0 { return false }
        if CGRectGeometry.iou(a, b) >= trackIoU { return true }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 && Float(inter / smaller) >= duplicateContainment
    }
}
