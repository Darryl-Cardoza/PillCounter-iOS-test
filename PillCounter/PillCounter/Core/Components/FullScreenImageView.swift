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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let proposed = lastScale * value
                                        scale = min(max(proposed, 1), 4)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale <= 1 {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                scale      = 1
                                                lastScale  = 1
                                                offset     = .zero
                                                lastOffset = .zero
                                            }
                                        } else {
                                            let clamped = clampedOffset(offset, in: geo.size, scale: scale)
                                            withAnimation(.spring(response: 0.25)) {
                                                offset     = clamped
                                                lastOffset = clamped
                                            }
                                        }
                                    },
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if scale > 1 {
                                            // Pan when zoomed in
                                            let proposed = CGSize(
                                                width:  lastOffset.width  + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                            offset = clampedOffset(proposed, in: geo.size, scale: scale)
                                        } else {
                                            // Dismiss drag when at normal scale
                                            if value.translation.height > 0 {
                                                offset = CGSize(width: 0, height: value.translation.height)
                                            }
                                        }
                                    }
                                    .onEnded { value in
                                        if scale > 1 {
                                            let proposed = CGSize(
                                                width:  lastOffset.width  + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                            let clamped = clampedOffset(proposed, in: geo.size, scale: scale)
                                            offset     = clamped
                                            lastOffset = clamped
                                        } else {
                                            // Dismiss if dragged down far enough
                                            if value.translation.height > 120 {
                                                onDismiss()
                                            } else {
                                                withAnimation(.spring(response: 0.3)) {
                                                    offset = .zero
                                                }
                                            }
                                        }
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if scale > 1 {
                                    scale      = 1
                                    lastScale  = 1
                                    offset     = .zero
                                    lastOffset = .zero
                                } else {
                                    scale     = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                }

                closeButton
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Clamp offset so image never pans beyond its zoomed edges
    private func clampedOffset(_ proposed: CGSize, in size: CGSize, scale: CGFloat) -> CGSize {
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
