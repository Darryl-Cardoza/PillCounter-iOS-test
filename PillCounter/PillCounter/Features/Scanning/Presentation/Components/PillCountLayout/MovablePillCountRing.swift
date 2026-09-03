//
//  MovablePillCountRing.swift
//  PillCounter
//
//  The count ring is the Add / All Done control itself:
//   • draggable — long-press (hold) to pick it up, then drag to reposition,
//   • tappable  — a tap calls `onAdd` (or `onAllDone` once the target is reached),
//   • target-aware — once `isTargetReached`, the ring tints to the "done" colour and
//     a tap calls `onAllDone` instead.
//

import SwiftUI

struct MovablePillCountRing: View {

    @EnvironmentObject private var appColors: AppColors

    let count: Int
    let isTargetReached: Bool
    let isAddDisabled: Bool
    let isLandscape: Bool
    let onAdd: () -> Void
    let onAllDone: () -> Void

    // Drag state — `committedOffset` is the resting position (nil = use default,
    // i.e. never moved), `dragOffset` is the live delta while dragging.
    @State private var committedOffset: CGSize? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var didLoadStoredOffset: Bool = false

    // Ookla-style ripple — animates while the target is reached ("All Done").
    @State private var rippleActive: Bool = false
    // Subtle "breathing" — the solid ring gently scales/glows in/out while
    // "All Done", giving the state a calm, alive feel beyond the ripple.
    @State private var donePulse: Bool = false

    // Edit-mode pulse — a dashed halo that breathes/rotates while the ring is
    // "picked up" (held), signalling that it can now be dragged/resized.
    @State private var editPulse: Bool = false
    @State private var editDashPhase: CGFloat = 0

    // ── Pinch-to-resize (experimental) ──────────────────────────────────────
    // `committedScale` is the resting zoom factor; `gestureScale` is the live
    // pinch delta. Session-only (not persisted). Clamped to [minScale, maxScale].
    @State private var committedScale: CGFloat = 1.0
    @State private var gestureScale: CGFloat = 1.0

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Unscaled base diameter for the current device / orientation.
    private var baseSizeUnscaled: CGFloat {
        let s: CGFloat = 120
        guard isIpad else { return s }
        return isLandscape ? s * 2.0 : s * 1.5
    }

    // Pinch limits, relative to the unscaled base size.
    private let minScale: CGFloat = 0.6
    private let maxScale: CGFloat = 1.8

    /// Effective resting scale, clamped to the allowed range.
    private var effectiveScale: CGFloat {
        min(max(committedScale * gestureScale, minScale), maxScale)
    }

    /// Actual ring diameter after pinch scaling.
    private var baseSize: CGFloat { baseSizeUnscaled * effectiveScale }

    /// Largest diameter that still fits the device's smaller screen dimension —
    /// keeps the ring within bounds on every device, regardless of pinch.
    private func maxDiameter(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.9
    }

    // Default resting position — right side, vertically centered (matches the mockup).
    private func defaultOffset(in size: CGSize) -> CGSize {
        CGSize(width: size.width * 0.30, height: 0)
    }

    /// Clamp the ring's centre offset (from screen centre) so the whole ring stays
    /// on screen. It may slide behind the top/bottom bars, but never off-screen.
    private func clamp(_ offset: CGSize, in size: CGSize) -> CGSize {
        // The ring is centred in the container, so the max offset from centre is
        // half the remaining space after the ring's radius.
        let radius = baseSize / 2
        let maxX = max((size.width  / 2) - radius, 0)
        let maxY = max((size.height / 2) - radius, 0)
        return CGSize(
            width:  min(max(offset.width,  -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    var body: some View {
        GeometryReader { geo in
            let resting = clamp(committedOffset ?? defaultOffset(in: geo.size), in: geo.size)
            ringContent
                .offset(
                    x: resting.width + dragOffset.width,
                    y: resting.height + dragOffset.height
                )
                // Long-press to drag (one finger) and pinch to resize (two fingers)
                // run simultaneously. A plain tap counts as Add. Attached here, on
                // ringContent itself (which is contentShape-clipped to the visible
                // circle) rather than after the maxWidth/maxHeight frame below —
                // otherwise the gesture's hit area would be the full-screen frame
                // and steal touches meant for the top/bottom bars.
                .gesture(dragGesture(in: geo.size).simultaneously(with: pinchGesture(in: geo.size)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                // Seed the resting position from the last-saved offset (once).
                .onAppear {
                    guard !didLoadStoredOffset else { return }
                    didLoadStoredOffset = true
                    if let saved = AppStorageManager.shared.pillCountRingOffset {
                        committedOffset = clamp(saved, in: geo.size)
                    }
                }
        }
    }

    // MARK: - Gestures

    /// Long-press to "pick up", then drag to move. Clamped to the screen.
    private func dragGesture(in size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture())
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if !isDragging {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isDragging = true
                        }
                    }
                    // Clamp live so the ring never crosses the screen edge.
                    let base = clamp(committedOffset ?? defaultOffset(in: size), in: size)
                    let proposed = CGSize(
                        width: base.width + drag.translation.width,
                        height: base.height + drag.translation.height
                    )
                    let clamped = clamp(proposed, in: size)
                    dragOffset = CGSize(
                        width: clamped.width - base.width,
                        height: clamped.height - base.height
                    )
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    let base = clamp(committedOffset ?? defaultOffset(in: size), in: size)
                    let dropped = clamp(
                        CGSize(
                            width: base.width + drag.translation.width,
                            height: base.height + drag.translation.height
                        ),
                        in: size
                    )
                    committedOffset = dropped
                    // Remember the drop position for next time.
                    AppStorageManager.shared.pillCountRingOffset = dropped
                }
                dragOffset = .zero
                // Animate back to the normal (dropped) size.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isDragging = false
                }
            }
    }

    /// Two-finger pinch to resize the ring between min and max radius.
    /// Session-only (experimental, not persisted).
    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                gestureScale = value
            }
            .onEnded { value in
                // Fold the gesture delta into the committed scale, clamped to the
                // allowed range AND to what fits the device's screen.
                let screenMaxScale = maxDiameter(in: size) / baseSizeUnscaled
                let upper = min(maxScale, screenMaxScale)
                let settled = min(max(committedScale * value, minScale), upper)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    committedScale = settled
                    gestureScale = 1.0
                    // Keep the (possibly now-larger) ring within the screen.
                    if let committed = committedOffset {
                        committedOffset = clamp(committed, in: size)
                    }
                }
            }
    }

    private var ringColor: Color {
        if isTargetReached { return appColors.primary }
        return isAddDisabled ? Color.gray : appColors.secondary
    }

    /// Same transparent dark fill used by the top/bottom bars.
    private let ringBackground = Color.black.opacity(0.45)

    private var ringContent: some View {
        ZStack {
            // Edit-mode halo — a dashed, slowly-rotating ring that breathes
            // while the ring is held, indicating it's now movable/resizable.
            if isDragging {
                Circle()
                    .stroke(
                        ringColor.opacity(0.9),
                        style: StrokeStyle(
                            lineWidth: isIpad ? 3 : 2,
                            lineCap: .round,
                            dash: [baseSize * 0.06, baseSize * 0.05],
                            dashPhase: editDashPhase
                        )
                    )
                    .frame(width: baseSize * 1.18, height: baseSize * 1.18)
                    .scaleEffect(editPulse ? 1.06 : 0.98)
                    .opacity(editPulse ? 0.35 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: editPulse
                    )
                    .transition(.scale.combined(with: .opacity))
            }

            // Transparent dark backing for the ring.
            Circle()
                .fill(ringBackground)
                .frame(width: baseSize, height: baseSize)

            // "All Done" ripple — three soft, staggered waves that grow OUTWARD
            // from the centre (the text) to the ring edge, clipped inside the ring
            // so they never spill past the outline. Layered above the backing but
            // below the outline and text.
            if isTargetReached {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(appColors.primary, lineWidth: isIpad ? 2 : 1.5)
                            // Full ring diameter at scale 1; starts tiny at the centre
                            // and expands to fill the ring, fading as it reaches the edge.
                            .frame(width: baseSize, height: baseSize)
                            .scaleEffect(rippleActive ? 1.0 : 0.05)
                            .opacity(rippleActive ? 0 : 0.6)
                            .animation(
                                .easeOut(duration: 3.0)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 1.0),
                                value: rippleActive
                            )
                    }
                }
                .frame(width: baseSize, height: baseSize)
                // Keep the waves strictly within the ring's circle.
                .clipShape(Circle())
            }

            Circle()
                .stroke(ringColor, style: StrokeStyle(lineWidth: isIpad ? 3 : 2, lineCap: .round))
                .frame(width: baseSize, height: baseSize)
                // Gentle breathing on the ring outline while "All Done".
                .scaleEffect(isTargetReached && donePulse ? 1.04 : 1.0)
                .shadow(
                    color: appColors.primary.opacity(isTargetReached && donePulse ? 0.7 : 0.25),
                    radius: isTargetReached ? (donePulse ? baseSize * 0.05 : baseSize * 0.02) : 0
                )
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: donePulse
                )

            // While the ring is an Add control it shows the count with an "Add"
            // label beneath it; once the target is reached it converts to
            // "All Done" (with the ripple above). The open-ended parent pour is
            // never target-reached, so it always shows the Add state — its step
            // is finished via the separate "Done" button in the bottom bar.
            if isTargetReached {
                Text(L10n.PillCount.allDone)
                    .font(.system(size: baseSize * 0.16, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    // Small breathing on the label so the centre feels alive — the
                    // ripple visually emanates from here.
                    .scaleEffect(donePulse ? 1.06 : 0.98)
                    .animation(
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: donePulse
                    )
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: baseSize * 0.04) {
                    Text("\(count)")
                        .font(.system(size: baseSize * 0.30, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(L10n.Common.add)
                        .font(.system(size: baseSize * 0.13, weight: .bold))
                        .foregroundStyle(isAddDisabled ? Color.white.opacity(0.4) : .white)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        // The ring itself is the tap target — a tap counts as Add / All Done.
        .contentShape(Circle())
        .onTapGesture { handleTap() }
        // Picked-up state — grows bigger while dragging, with a lifted shadow.
        // The scale change is animated by the gesture's withAnimation blocks.
        .scaleEffect(isDragging ? 1.18 : 1.0)
        .shadow(color: .black.opacity(isDragging ? 0.4 : 0), radius: isDragging ? 16 : 0, y: isDragging ? 8 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isTargetReached)
        .onAppear {
            rippleActive = isTargetReached
            donePulse = isTargetReached
        }
        .onChange(of: isTargetReached) { _, reached in
            rippleActive = reached
            donePulse = reached
        }
        // Start/stop the edit-mode halo animations alongside the picked-up state.
        .onChange(of: isDragging) { _, dragging in
            editPulse = dragging
            if dragging {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    editDashPhase = -baseSize * 0.5
                }
            } else {
                editDashPhase = 0
            }
        }
    }

    private func handleTap() {
        guard !isDragging else { return }
        if isTargetReached {
            onAllDone()
        } else {
            // Both the normal step and the open-ended parent pour commit via Add.
            // (The parent pour is finished by the bottom-bar "Done" button.)
            guard !isAddDisabled else { return }
            onAdd()
        }
    }
}
