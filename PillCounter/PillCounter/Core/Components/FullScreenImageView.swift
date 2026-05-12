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
    @State private var offset: CGSize = .zero

    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureDrag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale * gestureScale)
                        .offset(
                            x: boundedOffset(
                                proposed: offset.width + gestureDrag.width,
                                size: geo.size,
                                scale: scale * gestureScale
                            ).width,
                            y: boundedOffset(
                                proposed: offset.height + gestureDrag.height,
                                size: geo.size,
                                scale: scale * gestureScale
                            ).height
                        )
                        .gesture(pinchGesture)
                        .gesture(dragGesture(in: geo.size))
                        .onTapGesture(count: 2) {
                            handleDoubleTap()
                        }
                }

                closeButton
            }
        }
    }

    // MARK: - Gestures

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newScale = scale * value
                scale = min(max(newScale, 1), 4)

                if scale == 1 {
                    resetPosition()
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .updating($gestureDrag) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                if scale == 1 && value.translation.height > 140 {
                    onDismiss()
                    return
                }

                let newOffset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )

                offset = boundedOffset(
                    proposed: newOffset,
                    size: size,
                    scale: scale
                )
            }
    }

    // MARK: - Logic

    private func handleDoubleTap() {
        withAnimation(.easeInOut) {
            if scale > 1 {
                scale = 1
                resetPosition()
            } else {
                scale = 2
            }
        }
    }

    private func resetPosition() {
        withAnimation(.easeOut) {
            offset = .zero
            lastOffset = .zero
        }
    }

    /// Prevents image from leaving screen bounds
    private func boundedOffset(
        proposed: CGSize,
        size: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let imageWidth = size.width * scale
        let imageHeight = size.height * scale

        let horizontalLimit = max(0, (imageWidth - size.width) / 2)
        let verticalLimit = max(0, (imageHeight - size.height) / 2)

        return CGSize(
            width: min(max(proposed.width, -horizontalLimit), horizontalLimit),
            height: min(max(proposed.height, -verticalLimit), verticalLimit)
        )
    }

    private func boundedOffset(
        proposed: CGFloat,
        size: CGSize,
        scale: CGFloat
    ) -> CGSize {
        boundedOffset(
            proposed: CGSize(width: proposed, height: proposed),
            size: size,
            scale: scale
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
                        .foregroundColor(.white)
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
