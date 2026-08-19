//
//  FaceScanSurface.swift
//  PillCounter
//
//  The camera viewfinder shared by every face-scan screen: the live preview,
//  the face-position guide drawn over it, a progress indicator while a frame
//  is in flight, and the flip-camera control.
//
//  Extracted from FaceAuthenticationView so the session lock screen can show
//  the same viewfinder while driving its own view model — previously the lock
//  screen showed only a spinner, giving the user nothing to look at.
//

import SwiftUI

struct FaceScanSurface: View {

    @ObservedObject var cameraService: FaceCameraService
    @EnvironmentObject private var appColors: AppColors

    /// Drives the guide's colour and the progress indicator. Passed in rather
    /// than read from a view model so both the standalone auth screen and the
    /// lock overlay can feed it from whichever instance they own.
    let state: AuthenticationState

    /// Lock screen hides this — flipping to the rear camera mid-unlock is not
    /// a meaningful action there.
    var showsFlipCamera: Bool = true

    var body: some View {
        ZStack {
            FaceCameraPreview(
                session: cameraService.previewSession,
                deviceOrientation: cameraService.currentCameraOrientation,
                isMirrored: cameraService.cameraPosition == .front
            )
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            FaceGuideOverlay(color: guideColor, isActive: isProcessingFrame)

            if isProcessingFrame {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            if showsFlipCamera {
                flipCameraButton
            }
        }
    }

    private var isProcessingFrame: Bool {
        switch state {
        case .faceDetected, .qualityChecking, .generatingEmbedding,
             .comparing, .candidateFound, .confirmingIdentity:
            return true
        default:
            return false
        }
    }

    private var guideColor: Color {
        switch state {
        case .authenticated: return .green
        case .failed: return .red
        case .transientIssue: return .orange
        case .confirmingIdentity, .candidateFound: return appColors.primary
        default: return appColors.text.opacity(0.5)
        }
    }

    private var flipCameraButton: some View {
        Button {
            cameraService.flipCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(16)
    }
}

/// Face-position guide: a dimmed surround with a clear head-shaped cutout and
/// four corner brackets. Replaces the previous full-height rounded rectangle,
/// which read as a plain box rather than as "put your face here".
private struct FaceGuideOverlay: View {

    let color: Color
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // Head-sized ellipse, centred and slightly above middle so the
            // chin isn't cropped when the user fills the frame.
            let width = size.width * 0.68
            let height = min(size.height * 0.74, width * 1.32)
            let rect = CGRect(
                x: (size.width - width) / 2,
                y: (size.height - height) / 2 - size.height * 0.02,
                width: width,
                height: height
            )

            ZStack {
                // Dim everything outside the cutout so the eye is pulled to it.
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle()
                            .overlay {
                                Ellipse()
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }

                Ellipse()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                CornerBrackets(rect: rect.insetBy(dx: -14, dy: -14), color: color)
            }
            .animation(.easeInOut(duration: 0.25), value: color)
            .scaleEffect(isActive ? 1.015 : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.2),
                value: isActive
            )
        }
        .allowsHitTesting(false)
    }
}

/// Four L-shaped corner marks framing the cutout — the familiar "align here"
/// affordance from document/QR scanners.
private struct CornerBrackets: View {

    let rect: CGRect
    let color: Color

    private let armLength: CGFloat = 26
    private let lineWidth: CGFloat = 3

    var body: some View {
        Path { path in
            // Top-left
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + armLength))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + armLength, y: rect.minY))
            // Top-right
            path.move(to: CGPoint(x: rect.maxX - armLength, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + armLength))
            // Bottom-right
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - armLength))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - armLength, y: rect.maxY))
            // Bottom-left
            path.move(to: CGPoint(x: rect.minX + armLength, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - armLength))
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}
