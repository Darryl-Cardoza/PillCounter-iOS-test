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
// already-published pill detections and the chute segmentation result that the
// camera pipeline produces every frame.
//
// DISTANCE METRIC (matches Android CameraPreviewSection)
// ──────────────────────────────────────────────────────
//   distance = distance from the pill centre to the nearest point on the chute
//   BOUNDING BOX (clamp the pill centre into the chute rect, then measure). This
//   is the exact metric the Android overlay uses. It is SMOOTH and monotonic —
//   unlike measuring to the nearest mask pixel, whose jagged boundary makes two
//   adjacent pills' distances jitter and swap rank. A smooth metric is the first
//   half of killing the ping-pong. Falls back to the bottom-centre of the tray
//   (else the frame) when no chute is segmented this frame — also mirrors Android.
//
// RANK HYSTERESIS (anti-switching — the second half)
// ──────────────────────────────────────────────────
//   Even with a smooth metric, the pill sitting right at the Nth/(N+1)th boundary
//   flips highlight on sub-pixel jitter when two pills are packed close together.
//   So selection is STATEFUL with an enter/stay rule (same shape as the pill
//   detector's confidence hysteresis):
//
//     • A pill not currently highlighted ENTERS only if it ranks within the top
//       `excess` by distance (strict).
//     • A pill already highlighted STAYS as long as it still ranks within
//       `excess + stayBand` (looser) — it is only dropped once it falls clearly
//       outside the boundary, not when it wobbles one rank across it.
//
//   Pills carry fresh ids every frame, so "already highlighted" is resolved by
//   matching this frame's pill centres to last frame's highlighted centres within
//   `matchRadius`. A real change (pill removed, tray moved, count changed) moves
//   pills well beyond the band and the highlight follows immediately; only tie
//   noise is absorbed.
// ─────────────────────────────────────────────────────────────────────────────

import CoreGraphics
import CoreML

final class ChuteProximity {

    /// How many ranks of slack a already-highlighted pill gets before it is
    /// dropped. With excess = N, a highlighted pill stays highlighted while it
    /// ranks within the nearest N + stayBand pills; a non-highlighted pill must
    /// break into the strict top N to take a slot. 2 ranks comfortably covers the
    /// 1-rank wobble that two near-equidistant packed pills produce, without
    /// letting a genuinely-farther pill linger.
    private let stayBand = 2

    /// A current-frame pill is treated as "the same pill" as a previously
    /// highlighted one when its centre is within this distance (original-frame px,
    /// normalised by frame size below) of the remembered centre. Pills are matched
    /// by position because each frame mints fresh ids. Expressed as a FRACTION of
    /// the frame's larger side so it is resolution-independent.
    private let matchRadiusFraction: CGFloat = 0.035

    /// Centres (original-frame pixel space) of the pills highlighted last frame.
    private var previousHighlightedCentres: [CGPoint] = []

    /// Clears the remembered highlight so the next frame starts fresh. Call when
    /// the counting session restarts (pause/resume) or the dispense target changes.
    func reset() {
        previousHighlightedCentres = []
    }

    /// Returns the ids of the `excess` pills closest to the chute, with rank
    /// hysteresis so a near-tie between adjacent packed pills does not flip the
    /// highlight every frame.
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
            previousHighlightedCentres = []
            return []
        }

        let clampedExcess = min(excess, pills.count)

        // Anchor / metric setup (original-frame pixel space).
        let frameSize = pills[0].originalFrameSize
        let matchRadius = max(frameSize.width, frameSize.height) * matchRadiusFraction

        // Fallback anchor when no chute is segmented this frame: bottom-centre of
        // the tray, else bottom-centre of the frame. Mirrors Android.
        let fallback: CGPoint = {
            if let trayRect = tray?.rect {
                return CGPoint(x: trayRect.midX, y: trayRect.maxY)
            }
            return CGPoint(x: frameSize.width / 2, y: frameSize.height)
        }()

        // Distance² from a pill centre to the chute (clamped-into-rect) or to the
        // fallback anchor. Squared is fine — only the ordering matters.
        func dist2(_ c: CGPoint) -> CGFloat {
            if let r = chute?.rect {
                let nx = min(max(c.x, r.minX), r.maxX)
                let ny = min(max(c.y, r.minY), r.maxY)
                let dx = c.x - nx, dy = c.y - ny
                return dx * dx + dy * dy
            }
            let dx = c.x - fallback.x, dy = c.y - fallback.y
            return dx * dx + dy * dy
        }

        // Rank every pill by distance to the chute (nearest first). Stable sort,
        // so exact ties keep input order — deterministic frame to frame.
        let order = pills.indices.sorted { dist2(pills[$0].center) < dist2(pills[$1].center) }

        // rankOfPill[pillIndex] = its position in the nearest-first ordering.
        var rankOfPill = [Int](repeating: 0, count: pills.count)
        for (rank, pillIdx) in order.enumerated() { rankOfPill[pillIdx] = rank }

        // Was this pill highlighted last frame? Matched by centre proximity.
        let matchR2 = matchRadius * matchRadius
        func wasHighlighted(_ c: CGPoint) -> Bool {
            previousHighlightedCentres.contains { prev in
                let dx = prev.x - c.x, dy = prev.y - c.y
                return dx * dx + dy * dy <= matchR2
            }
        }

        // Enter/stay selection:
        //   • strict top `clampedExcess` always selected (ENTER).
        //   • a previously-highlighted pill within top `clampedExcess + stayBand`
        //     is also kept (STAY) — but only until we've filled `clampedExcess`
        //     slots total, prioritising the held pills so the set is stable.
        let stayLimit = clampedExcess + stayBand

        // First pass: keep previously-highlighted pills that are still within the
        // stay band. These have priority for the available slots.
        var chosenIdx: [Int] = []
        for pillIdx in order {                       // nearest-first
            if chosenIdx.count >= clampedExcess { break }
            if wasHighlighted(pills[pillIdx].center), rankOfPill[pillIdx] < stayLimit {
                chosenIdx.append(pillIdx)
            }
        }
        // Second pass: fill any remaining slots with the strictly-nearest pills
        // (ENTER), skipping ones already chosen.
        if chosenIdx.count < clampedExcess {
            for pillIdx in order {                   // nearest-first
                if chosenIdx.count >= clampedExcess { break }
                if !chosenIdx.contains(pillIdx) {
                    chosenIdx.append(pillIdx)
                }
            }
        }

        previousHighlightedCentres = chosenIdx.map { pills[$0].center }
        return Set(chosenIdx.map { pills[$0].id })
    }
}
