//
//  FaceAligner.swift
//  PillCounter
//
//  Aligns a detected face using ALL 5 YuNet landmarks before it is handed to
//  SFace. This is the ONE alignment implementation shared by enrollment and
//  (later) authentication (spec section 5/16) — never crop-and-resize the
//  raw bounding box directly.
//
//  Uses the full 5-point Umeyama similarity transform (uniform scale +
//  rotation + translation, least-squares over all 5 landmarks against the
//  canonical ArcFace/InsightFace 112×112 template) — the same alignment a
//  known-working reference implementation of this exact YuNet+SFace pipeline
//  uses. An earlier version of this file used only the 2 eye points, which
//  ignores nose/mouth agreement and introduces alignment error that shifts
//  the resulting embedding away from what SFace was trained to expect.
//

import CoreImage
import CoreVideo
import CoreGraphics

final class FaceAligner {

    static let shared = FaceAligner()
    private init() {}

    /// SFace input resolution (matches sface_112x112_float16.mlpackage).
    let outputSize: Int = 112

    /// Canonical ArcFace/InsightFace 112×112 destination template, in the
    /// same landmark order YuNet emits: right eye, left eye, nose tip,
    /// right mouth corner, left mouth corner. Verbatim reference values —
    /// do not "clean up" the asymmetry between the two eye y-coordinates,
    /// it's part of the template SFace was trained against.
    private let template112: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var outputBuffer: CVPixelBuffer?

    /// Aligns `detection`'s face region out of `pixelBuffer` into a
    /// 112×112 BGRA CVPixelBuffer ready for SFace. Returns nil if the
    /// least-squares fit is degenerate (near-zero source point spread) —
    /// callers should treat that as an alignment failure.
    func align(pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult) -> CVPixelBuffer? {
        let l = detection.landmarks
        let src: [CGPoint] = [l.rightEye, l.leftEye, l.nose, l.rightMouthCorner, l.leftMouthCorner]

        guard let transform = similarityTransform(from: src, to: template112) else { return nil }

        // `transform` is solved in pixel space (Y-down, origin top-left) —
        // same space as the landmark coordinates and OpenCV's warpAffine.
        // CIImage's coordinate space is Y-up with origin bottom-left, so the
        // matrix must be sandwiched between flips around the source height
        // (in) and destination height (out), or every non-zero rotation
        // comes out mirrored/misaligned even though pure scale+translate
        // (no rotation) happens to look fine. This was silently corrupting
        // every non-frontal enrollment/probe crop and is why probes could
        // drift onto the wrong enrolled user.
        let srcHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let flipIn = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -srcHeight)
        let flipOut = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(outputSize))
        let ciTransform = CGAffineTransform(
            a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: transform.tx, ty: transform.ty
        )
        let combined = flipIn.concatenating(ciTransform).concatenating(flipOut)

        let srcImage = CIImage(cvPixelBuffer: pixelBuffer)
        let transformed = srcImage.transformed(by: combined)

        if outputBuffer == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferWidthKey:  outputSize as CFNumber,
                kCVPixelBufferHeightKey: outputSize as CFNumber,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA as CFNumber,
            ]
            var outBuf: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, outputSize, outputSize,
                                      kCVPixelFormatType_32BGRA, attrs as CFDictionary,
                                      &outBuf) == kCVReturnSuccess, outBuf != nil else { return nil }
            outputBuffer = outBuf
        }
        guard let out = outputBuffer else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: outputSize, height: outputSize)
        let black = CIImage(color: .black).cropped(to: bounds)
        ciContext.render(transformed.composited(over: black), to: out, bounds: bounds,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        return out
    }

    /// Closed-form 2D Umeyama similarity transform (uniform scale + rotation
    /// + translation) mapping `src` points onto `dst` points in a
    /// least-squares sense. Equivalent to the general N-dimensional
    /// SVD-based Umeyama solution specialized to 2D — for 2D similarity
    /// transforms the SVD reduces to this direct formula, no linear-algebra
    /// library needed:
    ///
    ///   scale    = Σ(dst_c · rot(src_c)) / Σ(|src_c|²)
    ///   rotation = atan2(Σ(sx·dy - sy·dx), Σ(sx·dx + sy·dy))   (src_c → dst_c)
    ///
    /// where src_c/dst_c are the point sets centered on their own centroids.
    /// Returns nil if the source points are degenerate (coincident / zero
    /// spread), matching the reference implementation's guard.
    private func similarityTransform(from src: [CGPoint], to dst: [CGPoint]) -> CGAffineTransform? {
        guard src.count == dst.count, src.count >= 2 else { return nil }
        let n = Double(src.count)

        let srcMeanX = src.reduce(0) { $0 + $1.x } / CGFloat(n)
        let srcMeanY = src.reduce(0) { $0 + $1.y } / CGFloat(n)
        let dstMeanX = dst.reduce(0) { $0 + $1.x } / CGFloat(n)
        let dstMeanY = dst.reduce(0) { $0 + $1.y } / CGFloat(n)

        var sumSrcSq: Double = 0
        var sumCross: Double = 0   // Σ(sx·dx + sy·dy) — cosine-aligned component
        var sumSkew: Double = 0    // Σ(sx·dy - sy·dx) — sine-aligned component

        for i in 0..<src.count {
            let sx = Double(src[i].x - srcMeanX)
            let sy = Double(src[i].y - srcMeanY)
            let dx = Double(dst[i].x - dstMeanX)
            let dy = Double(dst[i].y - dstMeanY)

            sumSrcSq += sx * sx + sy * sy
            sumCross += sx * dx + sy * dy
            sumSkew  += sx * dy - sy * dx
        }

        guard sumSrcSq > 1e-9 else { return nil }

        // Treating each centered point pair as a complex number, the
        // optimal (scale · e^{iθ}) least-squares fit is
        // Σ(dst_c · conj(src_c)) / Σ|src_c|² — this is that ratio's modulus
        // and argument. (Complex-number form of the 2D Umeyama solution.)
        let rotation = atan2(sumSkew, sumCross)
        let scale = sqrt(sumCross * sumCross + sumSkew * sumSkew) / sumSrcSq

        let cosR = Float(cos(rotation))
        let sinR = Float(sin(rotation))
        let s = Float(scale)

        // Full affine: dst = R*S*(src - srcMean) + dstMean, expanded into
        // CGAffineTransform's (a b c d tx ty) so a single `transformed(by:)`
        // does center → rotate → scale → re-center in one pass.
        let a =  s * cosR
        let b =  s * sinR
        let c = -s * sinR
        let d =  s * cosR
        let tx = Float(dstMeanX) - a * Float(srcMeanX) - c * Float(srcMeanY)
        let ty = Float(dstMeanY) - b * Float(srcMeanX) - d * Float(srcMeanY)

        return CGAffineTransform(a: CGFloat(a), b: CGFloat(b), c: CGFloat(c), d: CGFloat(d),
                                 tx: CGFloat(tx), ty: CGFloat(ty))
    }
}
