//
//  FullScreenImageView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 23/04/26.
//
import SwiftUI

struct FullScreenImageView: View {

    let image: Image?
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @GestureState private var liveDrag: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    // ← liveMagnification and liveDrag applied here, not stored
                    let currentScale = min(max(lastScale * liveMagnification, 1), 4)
                    let currentOffset = clamped(
                        CGSize(
                            width:  offset.width,
                            height: offset.height
                        ),
                        in: geo.size,
                        scale: currentScale
                    )

                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(currentScale)
                        .offset(currentOffset)
                        .gesture(pinchGesture)
                        .simultaneousGesture(lastScale > 1 ? panGesture(in: geo.size) : nil)
                        .simultaneousGesture(scale <= 1 ? dismissDrag : nil)
                        // ← highPriorityGesture so double-tap fires before single-tap/drag
                        .highPriorityGesture(doubleTapGesture)
                }

                closeButton
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Double Tap
    // highPriorityGesture ensures this wins over simultaneousGestures
    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    if scale > 1 {
                        // Zoom out — reset everything
                        scale      = 1
                        lastScale  = 1
                        offset     = .zero
                        lastOffset = .zero
                    } else {
                        // Zoom in to 2.5×
                        scale     = 2.5
                        lastScale = 2.5
                    }
                }
            }
    }

    // MARK: - Pinch
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($liveMagnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newScale = min(max(lastScale * value, 1), 4)
                withAnimation(.spring(response: 0.25)) {
                    scale     = newScale
                    lastScale = newScale
                    if newScale <= 1 {
                        offset     = .zero
                        lastOffset = .zero
                    } else {
                        // Clamp offset after scale settles
                        offset     = clamped(offset, in: .init(width: 1, height: 1), scale: newScale)
                        lastOffset = offset
                    }
                }
            }
    }

    // MARK: - Pan
    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($liveDrag) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let newOffset = clamped(
                    CGSize(
                        width:  offset.width  + value.translation.width,
                        height: offset.height + value.translation.height
                    ),
                    in: size,
                    scale: scale
                )
                offset     = newOffset
                lastOffset = newOffset
            }
    }

    // MARK: - Dismiss drag (scale == 1 only)
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($liveDrag) { value, state, _ in
                if value.translation.height > 0 {
                    state = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.3)) {
                        offset = .zero
                    }
                }
            }
    }

    // MARK: - Clamp
    private func clamped(_ proposed: CGSize, in size: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, (size.width  * (scale - 1)) / 2)
        let maxY = max(0, (size.height * (scale - 1)) / 2)
        return CGSize(
            width:  min(max(proposed.width,  -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    // MARK: - Close Button
    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.85))
                        .padding()
                }
            }
            Spacer()
        }
    }
}

struct ZoomableImageViewer: View {
 
    let uiImage: UIImage
    let onDismiss: () -> Void
 
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
 
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
 
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, lastScale * value)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1 {
                                    withAnimation(.spring()) {
                                        scale = 1
                                        offset = .zero
                                    }
                                    lastScale = 1
                                    lastOffset = .zero
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
 
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
        // Double-tap to reset zoom
        .onTapGesture(count: 2) {
            withAnimation(.spring()) {
                scale = 1
                offset = .zero
                lastScale = 1
                lastOffset = .zero
            }
        }
    }
}
