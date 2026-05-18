//
//  BottomSheet.swift
//  Android-style BottomSheet for SwiftUI
//  • Portrait  -> slides up from bottom
//  • Landscape -> slides in from the right
//
//  Uses GeometryReader (width > height) to detect landscape reliably
//  across all iPhones and iPads.
//

import SwiftUI

// MARK: - Bottom Sheet Modifier
struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let dismissOnBackgroundTap: Bool
    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent

    /// Width of the side sheet in landscape
    private let sideSheetWidth: CGFloat = 380

    /// Corner radius of the sheet
    private let cornerRadius: CGFloat = 20

    /// Backdrop dim
    private let dimOpacity: Double = 0.45

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let isLandscape = geo.size.width > geo.size.height

                    ZStack {
                        if isPresented {
                            // Dim background
                            Color.black
                                .opacity(dimOpacity)
                                .ignoresSafeArea()
                                .transition(.opacity)
                                .onTapGesture {
                                    if dismissOnBackgroundTap {
                                        dismiss()
                                    }
                                }

                            // Sheet
                            sheetView(isLandscape: isLandscape, size: geo.size)
                                .transition(isLandscape ? .move(edge: .trailing)
                                                        : .move(edge: .bottom))
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .animation(.easeInOut(duration: 0.28), value: isPresented)
                }
            )
            // Fire onDismiss whenever the sheet transitions to hidden
            .onChange(of: isPresented) { newValue in
                if newValue == false {
                    onDismiss?()
                }
            }
    }

    // MARK: - Sheet placement
    @ViewBuilder
    private func sheetView(isLandscape: Bool, size: CGSize) -> some View {
        if isLandscape {
            // Right side sheet — full screen height, edge-to-edge
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                sheetContent()
                    .frame(width: min(sideSheetWidth, size.width * 0.6))
                    .frame(maxHeight: .infinity)
                    .clipShape(
                        RoundedCorners(radius: cornerRadius,
                                       corners: [.topLeft, .bottomLeft])
                    )
                    .shadow(color: .black.opacity(0.2),
                            radius: 10, x: -2, y: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        } else {
            // Bottom sheet — full width
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                sheetContent()
                    .frame(maxWidth: .infinity)
                    .clipShape(
                        RoundedCorners(radius: cornerRadius,
                                       corners: [.topLeft, .topRight])
                    )
                    .shadow(color: .black.opacity(0.2),
                            radius: 10, x: 0, y: -2)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func dismiss() {
        withAnimation { isPresented = false }
    }
}

// MARK: - Rounded Corners Shape (selective corners)
struct RoundedCorners: Shape {
    var radius: CGFloat = 20
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - View Extension
extension View {
    /// Android-style bottom sheet.
    /// Slides up from the bottom in portrait, in from the right in landscape.
    ///
    /// - Parameters:
    ///   - isPresented: Binding controlling sheet visibility.
    ///   - dismissOnBackgroundTap: If `true`, tapping the dimmed backdrop dismisses the sheet.
    ///     If `false`, the sheet can only be dismissed programmatically.
    ///   - onDismiss: Called whenever the sheet transitions from presented to hidden
    ///     (via backdrop tap or by setting `isPresented = false`).
    ///   - content: The sheet content view.
    func bottomSheet<Content: View>(
        isPresented: Binding<Bool>,
        dismissOnBackgroundTap: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(
            BottomSheetModifier(
                isPresented: isPresented,
                dismissOnBackgroundTap: dismissOnBackgroundTap,
                onDismiss: onDismiss,
                sheetContent: content
            )
        )
    }
}
