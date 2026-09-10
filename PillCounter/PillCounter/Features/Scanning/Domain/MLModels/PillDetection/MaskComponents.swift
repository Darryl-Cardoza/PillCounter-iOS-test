// MaskComponents.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// Connected-component helper for the tray segmentation masks.
//
// The tray/chute bounding box used to be the min/max of EVERY pixel the
// segmenter assigned to the class. One stray blob anywhere in the frame (a
// green notebook next to the tray classified as "tray") then stretched the box
// across both objects — and because the pill model runs on that box, the crop
// was mostly notebook and the pills shrank far below the size the model was
// trained at. Keeping only the largest 4-connected component gives a box and a
// mask that describe one physical object.
//
// 1:1 port of the Android `MaskComponents`. One instance per detector: the
// visited set and the flood-fill stack are reused across frames, so a call
// allocates only the result mask. Not thread-safe — same single-caller
// contract as the detector.
// ─────────────────────────────────────────────────────────────────────────────

final class MaskComponents {

    struct Component {
        /// Row-major size×size mask holding only this component's pixels.
        let mask: [Bool]
        let pixelCount: Int
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
        /// How many separate blobs the input mask had; 1 means nothing was discarded.
        let componentCount: Int
    }

    private let size: Int
    private let total: Int
    private var visited: [Bool]
    // Every pixel is pushed at most once (marked visited on push), so the
    // stack never needs more than `total` slots.
    private var stack: [Int32]
    private var sp = 0

    // Scratch written by flood().
    private var count = 0
    private var minX = 0
    private var minY = 0
    private var maxX = 0
    private var maxY = 0
    /// When non-empty, flood() also records the visited pixels here.
    private var collect: [Bool] = []

    init(size: Int) {
        self.size = size
        self.total = size * size
        self.visited = [Bool](repeating: false, count: total)
        self.stack = [Int32](repeating: 0, count: total)
    }

    /// Largest 4-connected component of `mask` (row-major size×size), or nil
    /// when the mask is empty. Ties go to the component encountered first in
    /// row-major order.
    func largest(_ mask: [Bool]) -> Component? {
        precondition(mask.count == total, "mask must be \(size)x\(size)")
        resetVisited()
        collect = []

        var bestSeed = -1
        var bestCount = 0
        var bestMinX = 0, bestMinY = 0, bestMaxX = 0, bestMaxY = 0
        var components = 0

        for seed in 0..<total where mask[seed] && !visited[seed] {
            components += 1
            flood(from: seed, mask: mask)
            if count > bestCount {
                bestCount = count
                bestSeed = seed
                bestMinX = minX; bestMinY = minY; bestMaxX = maxX; bestMaxY = maxY
            }
        }
        guard bestSeed >= 0 else { return nil }

        let componentMask: [Bool]
        if components == 1 {
            componentMask = mask
        } else {
            // Second pass over the winner only, writing its pixels to a fresh mask.
            resetVisited()
            collect = [Bool](repeating: false, count: total)
            flood(from: bestSeed, mask: mask)
            componentMask = collect
            collect = []
        }
        return Component(mask: componentMask, pixelCount: bestCount,
                         minX: bestMinX, minY: bestMinY, maxX: bestMaxX, maxY: bestMaxY,
                         componentCount: components)
    }

    private func resetVisited() {
        for i in 0..<total { visited[i] = false }
    }

    /// Iterative flood fill from `seed` over set pixels of `mask` not yet
    /// visited. Leaves the component's pixel count and bbox in the scratch
    /// fields, and marks the visited pixels in `collect` when it is non-empty.
    private func flood(from seed: Int, mask: [Bool]) {
        count = 0
        minX = size; minY = size; maxX = -1; maxY = -1
        sp = 0
        visited[seed] = true
        stack[sp] = Int32(seed); sp += 1
        let collecting = !collect.isEmpty
        while sp > 0 {
            sp -= 1
            let idx = Int(stack[sp])
            let x = idx % size
            let y = idx / size
            count += 1
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
            if collecting { collect[idx] = true }
            if x > 0        { push(idx - 1,    mask) }
            if x < size - 1 { push(idx + 1,    mask) }
            if y > 0        { push(idx - size, mask) }
            if y < size - 1 { push(idx + size, mask) }
        }
    }

    @inline(__always)
    private func push(_ idx: Int, _ mask: [Bool]) {
        if mask[idx] && !visited[idx] {
            visited[idx] = true
            stack[sp] = Int32(idx); sp += 1
        }
    }
}
