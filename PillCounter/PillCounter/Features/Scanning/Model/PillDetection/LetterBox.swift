//
//  LetterBox.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import UIKit
import CoreVideo

final class Letterbox {

    struct ScaleInfo {
        let scale: CGFloat
        let padX: CGFloat
        let padY: CGFloat
    }

    static var currentScaleInfo: ScaleInfo?

    private static let debug = true

    // Convert camera frame → letterboxed targetSize × targetSize
    static func preprocess(
        _ px: CVPixelBuffer,
        targetSize: Int
    ) -> CVPixelBuffer? {

        let frame = CIImage(cvPixelBuffer: px)
        let w = frame.extent.width
        let h = frame.extent.height

        if debug {
            print("""
            📸 [Letterbox] Incoming frame
            width  = \(w)
            height = \(h)
            """)
        }

        // SCALE
        let scale = min(
            CGFloat(targetSize) / w,
            CGFloat(targetSize) / h
        )

        let newW = w * scale
        let newH = h * scale

        // PADDING
        let padX = (CGFloat(targetSize) - newW) / 2
        let padY = (CGFloat(targetSize) - newH) / 2

        currentScaleInfo = ScaleInfo(
            scale: scale,
            padX: padX,
            padY: padY
        )

        if debug {
            print("""
            📐 [Letterbox] Scale calculation
            targetSize = \(targetSize)
            scale      = \(scale)

            resized width  = \(newW)
            resized height = \(newH)

            padX = \(padX)
            padY = \(padY)
            """)
        }

        // RESIZE + PAD
        let resized = frame
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: padX, y: padY))

        let context = CIContext()
        var buffer: CVPixelBuffer?

        let attrs: CFDictionary = [
            kCVPixelBufferWidthKey: targetSize,
            kCVPixelBufferHeightKey: targetSize,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ] as CFDictionary

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetSize,
            targetSize,
            kCVPixelFormatType_32BGRA,
            attrs,
            &buffer
        )

        guard let output = buffer else {
            if debug {
                print("❌ [Letterbox] Failed to create output pixel buffer")
            }
            return nil
        }

        context.render(
            resized,
            to: output,
            bounds: CGRect(
                x: 0,
                y: 0,
                width: targetSize,
                height: targetSize
            ),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        if debug {
            print("""
            🧱 [Letterbox] Output buffer sent to model
            width  = \(CVPixelBufferGetWidth(output))
            height = \(CVPixelBufferGetHeight(output))
            format = BGRA
            """)
        }

        return output
    }
}

