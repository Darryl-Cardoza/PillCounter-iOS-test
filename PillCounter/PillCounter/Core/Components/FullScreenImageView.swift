//
//  FullScreenImageView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 23/04/26.
//
import SwiftUI


struct FullScreenImageView: View {

    // Decrypt+decode happens per-page in FullScreenImagePage, keyed off this path —
    // pre-decoding every path here would put a whole scan run's photos on the main
    // thread on first render instead of one at a time as the user swipes.
    let imagePaths: [String]
    let onDismiss: () -> Void

    @State private var currentIndex: Int

    init(image: Image?, onDismiss: @escaping () -> Void) {
        self.imagePaths = []
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: 0)
        self.preloadedImage = image
    }

    init(imagePaths: [String], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.imagePaths = imagePaths
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
        self.preloadedImage = nil
    }

    // Legacy single-image path (already-decoded Image, no file to key a reload off of).
    private let preloadedImage: Image?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let preloadedImage {
                FullScreenImagePage(image: preloadedImage, onDismiss: onDismiss)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(imagePaths.indices, id: \.self) { index in
                        FullScreenImagePage(imagePath: imagePaths[index], onDismiss: onDismiss)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            closeButton
        }
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

// MARK: - Single zoomable/pannable/dismissable page
private struct FullScreenImagePage: View {

    private let imagePath: String?
    private let preloadedImage: Image?
    let onDismiss: () -> Void

    @State private var loadedImage: Image?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(image: Image, onDismiss: @escaping () -> Void) {
        self.imagePath = nil
        self.preloadedImage = image
        self.onDismiss = onDismiss
    }

    init(imagePath: String, onDismiss: @escaping () -> Void) {
        self.imagePath = imagePath
        self.preloadedImage = nil
        self.onDismiss = onDismiss
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image = preloadedImage ?? loadedImage {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture(in: geo.size))
                // Pan/dismiss drag is only attached when zoomed. At scale 1 no
                // DragGesture sits in the arena at all, so TabView's own swipe
                // recognizer is free to win horizontal drags for paging; vertical
                // dismiss-by-drag is intentionally dropped in favor of the close
                // button at scale 1 to avoid re-introducing the conflict.
                .gesture(scale > 1 ? AnyGesture(panGesture(in: geo.size)) : nil)
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
                .task(id: imagePath) {
                    guard let imagePath else { return }
                    let path = imagePath
                    let image = await Task.detached(priority: .userInitiated) {
                        PhotoFileManager.shared.loadImage(from: path)
                    }.value
                    loadedImage = image
                }
        }
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
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
                    let clamped = clampedOffset(offset, in: size, scale: scale)
                    withAnimation(.spring(response: 0.25)) {
                        offset     = clamped
                        lastOffset = clamped
                    }
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let proposed = CGSize(
                    width:  lastOffset.width  + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, in: size, scale: scale)
            }
            .onEnded { value in
                let proposed = CGSize(
                    width:  lastOffset.width  + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                let clamped = clampedOffset(proposed, in: size, scale: scale)
                offset     = clamped
                lastOffset = clamped
            }
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
            .ignoresSafeArea(.all, edges: [.leading, .trailing, .bottom])
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
