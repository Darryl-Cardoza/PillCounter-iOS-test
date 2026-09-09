//
//  LetterBox.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import UIKit
import CoreVideo
import CoreImage

/// Letterboxes a camera frame — or a rectangular region of it — into a square
/// BGRA pixel buffer for CoreML.
///
/// `ScaleInfo` maps source-frame pixels (top-left origin, as the decoders use)
/// to letterbox pixels:  x_in = (x_src - offsetX) * scale + padX.
/// `offsetX/offsetY` are 0 for a whole-frame letterbox and the crop's top-left
/// otherwise, so a decoder can map boxes straight back into full-frame
/// coordinates whatever region was fed to the model.
final class Letterbox {

    struct ScaleInfo {
        let scale: CGFloat
        let padX: CGFloat
        let padY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        init(scale: CGFloat, padX: CGFloat, padY: CGFloat, offsetX: CGFloat = 0, offsetY: CGFloat = 0) {
            self.scale = scale
            self.padX = padX
            self.padY = padY
            self.offsetX = offsetX
            self.offsetY = offsetY
        }
    }

    /// Scale info of the most recent whole-frame `preprocess` call. Kept for
    /// callers that still read it; the pill path uses the value `letterbox`
    /// returns instead, so two detectors can never race on it.
    static var currentScaleInfo: ScaleInfo?

    // CIContext is thread-safe and expensive to create; share one.
    private static let context = CIContext()

    /// Letterbox the whole frame to `targetSize`×`targetSize`.
    static func preprocess(_ px: CVPixelBuffer, targetSize: Int) -> CVPixelBuffer? {
        guard let result = letterbox(px, targetSize: targetSize, cropRect: nil) else { return nil }
        currentScaleInfo = result.info
        return result.buffer
    }

    /// Letterbox `cropRect` (top-left pixel coordinates; nil = whole frame) to a
    /// square buffer. Pixels outside the rect never reach the output — the
    /// padding stays black — so clutter around a tray crop is not shown to the model.
    static func letterbox(_ px: CVPixelBuffer,
                          targetSize: Int,
                          cropRect: CGRect?) -> (buffer: CVPixelBuffer, info: ScaleInfo)? {

        var image = CIImage(cvPixelBuffer: px)
        let frameH = image.extent.height
        var srcW = image.extent.width
        var srcH = frameH
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if let crop = cropRect {
            // CIImage's origin is bottom-left; the app's rects are top-left.
            let ciCrop = CGRect(x: crop.minX,
                                y: frameH - crop.maxY,
                                width: crop.width,
                                height: crop.height)
                .intersection(image.extent)
            guard !ciCrop.isNull, ciCrop.width > 0, ciCrop.height > 0 else { return nil }
            image = image
                .cropped(to: ciCrop)
                .transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY))
            srcW = ciCrop.width
            srcH = ciCrop.height
            offsetX = ciCrop.minX
            offsetY = frameH - ciCrop.maxY
        }

        let size = CGFloat(targetSize)
        let scale = min(size / srcW, size / srcH)
        let newW = srcW * scale
        let newH = srcH * scale
        let padX = (size - newW) / 2
        let padY = (size - newH) / 2

        // Centred padding is symmetric, so the bottom-left/top-left flip cancels:
        // letterbox row r of the output corresponds to source row (r - padY)/scale.
        let resized = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: padX, y: padY))

        let attrs: CFDictionary = [
            kCVPixelBufferWidthKey: targetSize,
            kCVPixelBufferHeightKey: targetSize,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ] as CFDictionary

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, targetSize, targetSize,
                            kCVPixelFormatType_32BGRA, attrs, &buffer)
        guard let output = buffer else { return nil }

        context.render(resized,
                       to: output,
                       bounds: CGRect(x: 0, y: 0, width: size, height: size),
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let info = ScaleInfo(scale: scale, padX: padX, padY: padY, offsetX: offsetX, offsetY: offsetY)
        return (output, info)
    }
}
