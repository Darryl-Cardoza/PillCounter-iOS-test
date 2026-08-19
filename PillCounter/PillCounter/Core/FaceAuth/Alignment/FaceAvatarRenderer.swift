//
//  FaceAvatarRenderer.swift
//  PillCounter
//
//  Turns an enrollment camera frame plus its detection into the square
//  head-and-shoulders thumbnail shown in the Quick Access Users row.
//
//  Deliberately NOT FaceAligner: that produces the 112×112 landmark-warped
//  input SFace was trained on, which is a recognition tensor, not a portrait —
//  it is tightly cropped to the facial features and rotated to a canonical
//  template, so it looks wrong to a human. This renders a plain padded crop of
//  the detection box instead, keeping the pose the user actually held.
//
//  The incoming buffer is already upright and (for the front camera) mirrored,
//  because FaceCameraService sets videoRotationAngle/isVideoMirrored on the
//  data-output connection — so no orientation correction happens here.
//

import CoreImage
import CoreVideo
import UIKit

enum FaceAvatarRenderer {

    /// Output edge length. Four times the 64pt display size covers a 3x screen
    /// with room to spare, and keeps the JPEG small.
    static let outputSize: CGFloat = 256

    /// Fraction of the detection box added on every side, so the thumbnail
    /// reads as a portrait (hair, chin, some shoulder) rather than a tight
    /// face-only crop.
    static let paddingRatio: CGFloat = 0.4

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Renders `detection`'s face region out of `pixelBuffer` as a square
    /// thumbnail. Returns nil if the crop lands outside the frame or the
    /// rasterization fails — the caller treats that as "no avatar", never as an
    /// enrollment failure.
    static func makeAvatar(pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult) -> UIImage? {
        let frameWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let frameHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard frameWidth > 0, frameHeight > 0 else { return nil }

        guard let cropRect = squareCropRect(
            around: detection.boundingBox,
            frameSize: CGSize(width: frameWidth, height: frameHeight)
        ) else { return nil }

        let image = CIImage(cvPixelBuffer: pixelBuffer)

        // Detection coordinates are Y-down from the top-left; CIImage is Y-up
        // from the bottom-left, so the crop rect has to be flipped vertically.
        let flippedRect = CGRect(
            x: cropRect.origin.x,
            y: frameHeight - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height
        )

        let cropped = image.cropped(to: flippedRect)
        guard !cropped.extent.isEmpty else { return nil }

        let scale = outputSize / cropped.extent.width
        let scaled = cropped
            // `cropped` keeps the original image's extent origin; move it back
            // to zero so the scale (and the render below) act on the crop
            // itself rather than on its offset within the full frame.
            .transformed(by: CGAffineTransform(translationX: -cropped.extent.origin.x, y: -cropped.extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Expands `boundingBox` by `paddingRatio`, squares it off around its own
    /// centre, and clamps it inside the frame. Returns nil if the box is
    /// degenerate or the frame cannot contain a square crop at all.
    ///
    /// Squaring happens before clamping and the side length is capped to the
    /// smaller frame dimension, so the result stays square — a non-square crop
    /// would be distorted by the `scaledToFill` thumbnail.
    static func squareCropRect(around boundingBox: CGRect, frameSize: CGSize) -> CGRect? {
        guard boundingBox.width > 0, boundingBox.height > 0 else { return nil }
        guard frameSize.width > 0, frameSize.height > 0 else { return nil }

        let padded = boundingBox.insetBy(
            dx: -boundingBox.width * paddingRatio,
            dy: -boundingBox.height * paddingRatio
        )

        let side = min(max(padded.width, padded.height), min(frameSize.width, frameSize.height))
        let centre = CGPoint(x: padded.midX, y: padded.midY)

        // Clamp the origin rather than the rect, so shifting a crop that hangs
        // off an edge back inside the frame preserves the full side length
        // instead of trimming it.
        let originX = min(max(centre.x - side / 2, 0), frameSize.width - side)
        let originY = min(max(centre.y - side / 2, 0), frameSize.height - side)

        return CGRect(x: originX, y: originY, width: side, height: side)
    }
}
