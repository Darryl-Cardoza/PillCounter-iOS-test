// ChuteProximity.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// PURPOSE
// ───────
// Post-processing helper for the "excess pills near the chute" overlay.
//
// In the dispense flow there is a TARGET quantity. When the tray holds more pills
// than the target, the operator should remove the surplus — and the most natural
// pills to remove are the ones closest to the chute (the dispenser opening). This
// helper picks those `excess` pills so the overlay can colour them differently.
//
// It does NOT touch the ML models or change any detection — it only reads the
// already-produced pill detections and the chute segmentation result.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THE PREVIOUS APPROACH PING-PONGED
// ─────────────────────────────────────
// The old picker re-ranked the LIVE per-frame detections by raw distance, then
// tried to stabilise with a rank band. Two problems made packed pills swap the
// highlight every frame:
//
//   1. RAW distance jitters. Detector boxes wobble ±a few px frame-to-frame, so
//      two near-equidistant pills flip rank order constantly. A rank band can't
//      help when the underlying *metric* is noisy.
//   2. NO PERSISTENT IDENTITY. Pills get fresh UUIDs every frame, so "was this
//      highlighted last frame?" was reconstructed by centre proximity — and with
//      two pills close together that match attaches to the wrong physical pill.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE FIX — PERSISTENT TRACKS + SMOOTHED DISTANCE + MARGIN-BASED STEAL
// ─────────────────────────────────────────────────────────────────────────────
//   • TRACKS: we keep a small set of persistent "pill tracks", each matched to
//     this frame's nearest detection. A track survives short misses, so identity
//     is stable across frames (no fresh-UUID re-matching of the *highlight*).
//
//   • SMOOTHED DISTANCE: each track holds an EMA-smoothed distance-to-chute, so
//     the value we rank on stops wobbling on sub-pixel box jitter.
//
//   • MAXIMALLY-STICKY SELECTION: a track that is currently highlighted KEEPS its
//     slot until a non-highlighted track is closer by a clear MARGIN (a fraction
//     of the frame), not merely one rank closer. Two near-equal pills therefore
//     never trade the highlight — the incumbent wins all ties. The highlight only
//     moves on a real change (a pill removed, the tray moved, the count changed),
//     because those move distances well past the margin.
// ─────────────────────────────────────────────────────────────────────────────

import CoreGraphics
import CoreML

final class ChuteProximity {

    // MARK: - Tuning

    /// EMA smoothing factor for each track's distance-to-chute. Lower = smoother
    /// (more lag, less jitter). 0.4 absorbs box wobble while still following a
    /// real move within a couple of frames.
    private let distanceSmoothing: CGFloat = 0.4

    /// A current-frame detection is bound to an existing track when its centre is
    /// within this fraction of the frame's larger side. Also the radius used to
    /// retire stale tracks. 0.04 ≈ one pill-width — large enough to follow a pill
    /// that shifts as the tray is nudged, small enough not to jump between
    /// neighbours.
    private let matchRadiusFraction: CGFloat = 0.04

    /// Tie tolerance, as a fraction of the frame's larger side. Two pills whose
    /// smoothed distances are within this band are treated as "tied" — the
    /// incumbent (already-highlighted) one wins, so sub-pixel wobble between two
    /// near-equidistant pills never swaps the highlight. Kept SMALL (jitter-sized,
    /// ~1.5% of frame ≈ a few px) so a pill that is genuinely closer than the
    /// incumbent — by more than wobble — is NOT blocked; that was the bug where a
    /// clearly-nearer pill stayed unmarked while a farther one held its slot.
    private let tieBandFraction: CGFloat = 0.015

    /// A challenger must out-rank the incumbent (beyond the tie band) for this many
    /// CONSECUTIVE frames before the swap commits. This is what actually kills
    /// ping-pong: a one-frame fluke can't move the highlight, but a real, sustained
    /// "this pill is nearer" takes effect within a few frames. Combined with the
    /// tie band, a genuine near pill gets marked quickly while jitter is ignored.
    private let stealConfirmFrames: Int = 3

    /// Frames a track may go unmatched before it is retired. Bridges a 1-frame
    /// detector miss so a highlighted pill doesn't drop (and let a neighbour grab
    /// the slot) just because the model blinked for one frame.
    private let maxTrackMisses: Int = 2

    // MARK: - Track

    private struct Track {
        let id: Int
        var center: CGPoint
        var smoothedDist: CGFloat   // EMA of distance-to-chute (px)
        var misses: Int             // consecutive frames unmatched
        var highlighted: Bool       // currently part of the excess set
        /// Consecutive frames this track has out-ranked a highlighted incumbent
        /// (beyond the tie band) while NOT itself highlighted. Drives the
        /// confirm-frames steal. Reset to 0 whenever it isn't pressuring.
        var stealPressure: Int = 0
    }

    private var tracks: [Track] = []
    private var nextTrackID = 0

    // MARK: - Reset

    /// Clears all track state so the next frame starts fresh. Call when the
    /// counting session restarts (pause/resume) or the dispense target changes.
    func reset() {
        tracks.removeAll()
        nextTrackID = 0
    }

    // MARK: - Public API

    /// Returns the ids of the `excess` pills nearest the chute, using persistent
    /// tracking + distance smoothing for a steady ranking, then a jitter-band +
    /// confirm-frames steal so a genuinely-nearer pill is marked quickly while two
    /// near-equidistant packed pills never trade the highlight on sub-pixel wobble.
    ///
    /// - Parameters:
    ///   - pills:  Live per-frame pill detections (centres in original-frame px).
    ///   - chute:  The `.chute` segmentation result for this frame, if any.
    ///   - tray:   The `.tray` segmentation result, used only for the no-chute
    ///             fallback anchor (bottom-centre of the tray).
    ///   - excess: How many pills to mark (already computed as
    ///             max(0, stableCount − target) by the caller). Clamped to count.
    /// - Returns: A set of `DetectionResult.id` to highlight. Empty when there is
    ///            no excess or no pills.
    func nearChuteIDs(pills: [DetectionResult],
                      chute: TrayResult?,
                      tray: TrayResult?,
                      excess: Int) -> Set<UUID> {

        guard excess > 0, !pills.isEmpty else {
            tracks.removeAll()
            return []
        }

        let clampedExcess = min(excess, pills.count)

        // ── Geometry setup (original-frame pixel space) ──────────────────────
        let frameSize = pills[0].originalFrameSize
        let frameSpan = max(frameSize.width, frameSize.height)
        let matchR  = frameSpan * matchRadiusFraction
        let matchR2 = matchR * matchR
        let tieBand = frameSpan * tieBandFraction

        // Fallback anchor when no chute is segmented this frame: bottom-centre of
        // the tray, else bottom-centre of the frame.
        let fallback: CGPoint = {
            if let trayRect = tray?.rect {
                return CGPoint(x: trayRect.midX, y: trayRect.maxY)
            }
            return CGPoint(x: frameSize.width / 2, y: frameSize.height)
        }()

        // Distance from a pill centre to the chute (clamped-into-rect) or to the
        // fallback anchor. Smooth + monotonic so adjacent pills don't jitter rank.
        func distance(_ c: CGPoint) -> CGFloat {
            let anchor: CGPoint
            if let r = chute?.rect {
                anchor = CGPoint(x: min(max(c.x, r.minX), r.maxX),
                                 y: min(max(c.y, r.minY), r.maxY))
            } else {
                anchor = fallback
            }
            let dx = c.x - anchor.x, dy = c.y - anchor.y
            return (dx * dx + dy * dy).squareRoot()
        }

        // ── Step 1: bind each detection to a track ───────────────────────────
        // Greedily match every detection to the nearest existing track within
        // matchR. Unmatched detections spawn new tracks; matched tracks update
        // their centre and EMA distance.
        var detTrackID = [Int?](repeating: nil, count: pills.count)   // pill → track id
        var usedTrack = Set<Int>()

        for (i, pill) in pills.enumerated() {
            let c = pill.center
            var bestIdx: Int? = nil
            var bestD2 = matchR2
            for (ti, t) in tracks.enumerated() where !usedTrack.contains(t.id) {
                let dx = t.center.x - c.x, dy = t.center.y - c.y
                let d2 = dx * dx + dy * dy
                if d2 <= bestD2 { bestD2 = d2; bestIdx = ti }
            }
            if let ti = bestIdx {
                let d = distance(c)
                tracks[ti].center = c
                tracks[ti].smoothedDist += distanceSmoothing * (d - tracks[ti].smoothedDist)
                tracks[ti].misses = 0
                usedTrack.insert(tracks[ti].id)
                detTrackID[i] = tracks[ti].id
            } else {
                let d = distance(c)
                let t = Track(id: nextTrackID, center: c, smoothedDist: d,
                              misses: 0, highlighted: false)
                tracks.append(t)
                usedTrack.insert(nextTrackID)
                detTrackID[i] = nextTrackID
                nextTrackID += 1
            }
        }

        // ── Step 2: age + retire tracks not seen this frame ──────────────────
        for ti in tracks.indices where !usedTrack.contains(tracks[ti].id) {
            tracks[ti].misses += 1
        }
        tracks.removeAll { $0.misses > maxTrackMisses }

        // Only tracks matched THIS frame are eligible to be highlighted (we draw
        // on live detections). Sorted nearest-first by smoothed distance.
        let liveTrackIdx = tracks.indices
            .filter { usedTrack.contains(tracks[$0].id) }
            .sorted { tracks[$0].smoothedDist < tracks[$1].smoothedDist }

        // ── Step 3: nearest-N with jitter-band + confirm-frames steal ────────
        // The IDEAL set is simply the strict nearest `clampedExcess` by smoothed
        // distance — that is always "correct". We start from the incumbents to
        // resist jitter, then let an ideal-but-blocked challenger take a slot only
        // after it has been clearly nearer (beyond the tie band) for a few frames.
        // This fixes the "near pill unmarked, far pill marked" case (a genuinely
        // closer pill is no longer blocked by a pill-width margin) while still
        // refusing to swap on sub-pixel ties.
        let liveSet = Set(liveTrackIdx)

        // 3a. Start the working set from current incumbents (nearest-first),
        // then fill empty slots with the strictly-nearest non-incumbents.
        var selected: [Int] = []
        for ti in liveTrackIdx where tracks[ti].highlighted {
            if selected.count >= clampedExcess { break }
            selected.append(ti)
        }
        if selected.count < clampedExcess {
            for ti in liveTrackIdx where !tracks[ti].highlighted {
                if selected.count >= clampedExcess { break }
                selected.append(ti)
            }
        }

        // 3b. The ideal (strict nearest-N) set — the challengers allowed to steal.
        let idealSelected = Array(liveTrackIdx.prefix(clampedExcess))

        // 3c. Confirm-frames steal. A track that SHOULD be in (ideal) but isn't
        // builds pressure each frame it out-ranks the worst selected incumbent by
        // more than the tie band; once pressure reaches the confirm count, it swaps
        // in. Any track not currently pressuring decays its counter to 0.
        if clampedExcess > 0, selected.count == clampedExcess {
            var selectedSet = Set(selected)

            // The set of challengers that actually pressure a slot THIS frame.
            // Anything not in here decays to 0 below, so pressure only survives
            // while the same pill keeps out-ranking the incumbent every frame.
            var pressuringThisFrame = Set<Int>()

            var changed = true
            while changed {
                changed = false
                // Worst (farthest) currently-selected track.
                guard let worstPos = selected.enumerated()
                    .max(by: { tracks[$0.element].smoothedDist < tracks[$1.element].smoothedDist })?.offset
                else { break }
                let worstIdx  = selected[worstPos]
                let worstDist = tracks[worstIdx].smoothedDist

                // Best challenger: an ideal track that isn't selected yet, nearest first.
                guard let ch = idealSelected.first(where: { !selectedSet.contains($0) })
                else { break }

                // Only pressure if it clears the tie band; otherwise it's a tie and
                // the incumbent keeps the slot.
                if worstDist - tracks[ch].smoothedDist > tieBand {
                    pressuringThisFrame.insert(ch)
                    tracks[ch].stealPressure += 1
                    if tracks[ch].stealPressure >= stealConfirmFrames {
                        // Commit the swap.
                        selected[worstPos] = ch
                        selectedSet.remove(worstIdx)
                        selectedSet.insert(ch)
                        tracks[ch].stealPressure = 0
                        pressuringThisFrame.remove(ch)
                        changed = true
                    }
                }
            }

            // Decay pressure for every track that did NOT pressure this frame, so a
            // momentary blip can't accumulate toward a steal over many frames.
            for ti in tracks.indices where !pressuringThisFrame.contains(ti) {
                tracks[ti].stealPressure = 0
            }
        }

        // ── Step 4: commit highlight flags + map back to live detection ids ──
        let selectedSet = Set(selected)
        for ti in tracks.indices {
            tracks[ti].highlighted = liveSet.contains(ti) && selectedSet.contains(ti)
        }

        // Map chosen tracks → the ids of the live detections bound to them.
        var result = Set<UUID>()
        for (i, pill) in pills.enumerated() {
            if let tid = detTrackID[i],
               let ti = tracks.firstIndex(where: { $0.id == tid }),
               selectedSet.contains(ti) {
                result.insert(pill.id)
            }
        }
        return result
    }
}
