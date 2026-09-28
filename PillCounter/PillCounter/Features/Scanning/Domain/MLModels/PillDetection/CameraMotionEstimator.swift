//
//  CameraMotionEstimator.swift
//  PillCounter
//
//  Frame-to-frame camera motion for PillTracker (iOS counterpart of the Android
//  OpenCV phase-correlation estimator, using Vision's translational registration).
//

import CoreImage
import CoreVideo
import Vision

/// Global camera motion between consecutive frames, in frame pixels: a pan that
/// moves every pill 12 px to the right yields dx ≈ +12. Registers two frames
/// downscaled into a reused buffer via `VNTranslationalImageRegistrationRequest`
/// — insensitive to the repeating pill pattern that defeats nearest-neighbour
/// voting in a dense tray, since tray edges/chute/background fix the alignment.
/// `PillTracker.resolveShift` validates the sign against its own detections, so
/// the axis convention here can never make association worse than no shift.
/// Not thread-safe; the camera pipeline calls it once per frame.
final class CameraMotionEstimator {

    struct Shift {
        let dx: CGFloat
        let dy: CGFloat
    }

    private static let side = 256

    private var buffers: [CVPixelBuffer] = []
    private var current = 0
    private var hasPrevious = false
    private var disabled = false

    /// Nil on the first frame after a reset, or when registration fails.
    func estimate(_ frame: CVPixelBuffer) -> Shift? {
        if disabled { return nil }
        if buffers.count < 2 {
            guard let a = Self.makeBuffer(), let b = Self.makeBuffer() else {
                disabled = true
                return nil
            }
            buffers = [a, b]
        }

        let curIdx = current
        let prevIdx = 1 - current
        current = prevIdx

        let image = CIImage(cvPixelBuffer: frame)
        let scale = CGFloat(Self.side) / max(image.extent.width, image.extent.height)
        let bounds = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        Letterbox.context.render(image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
                       to: buffers[curIdx],
                       bounds: bounds,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        guard hasPrevious else {
            hasPrevious = true
            return nil
        }

        let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: buffers[curIdx])
        let handler = VNImageRequestHandler(cvPixelBuffer: buffers[prevIdx], options: [:])
        do {
            try handler.perform([request])
        } catch {
            AppLogger.shared.debug("CameraMotionEstimator: motion estimation request failed, no shift computed this frame")
            return nil
        }
        guard let observation = request.results?.first else { return nil }

        // alignmentTransform moves the current frame onto the previous one, so the
        // scene's motion previous → current is its negation, back in frame pixels.
        let t = observation.alignmentTransform
        return Shift(dx: -t.tx / scale, dy: -t.ty / scale)
    }

    /// Forget the previous frame (new scene).
    func reset() {
        hasPrevious = false
    }

    private static func makeBuffer() -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: side as CFNumber,
            kCVPixelBufferHeightKey: side as CFNumber,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA as CFNumber,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, side, side,
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary, &buffer)
        return status == kCVReturnSuccess ? buffer : nil
    }
}
