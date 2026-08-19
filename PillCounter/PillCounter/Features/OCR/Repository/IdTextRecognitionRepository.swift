//
//  IdTextRecognitionRepository.swift
//  PillCounter
//
//  The one file in the OCR feature that imports Vision. Swapping OCR engines,
//  or adding a PDF417 barcode path later, is a change to this file only —
//  see plans/face-auth/ocr/19-08-2026-12-31-ocr-id-scan.md §2.1.
//

import CoreVideo
import Vision

protocol IdTextRecognitionRepositoryProtocol {
    /// Recognized lines with pixel-height boxes, or [] when nothing was read.
    /// Called off the main thread; must not return until recognition finishes.
    func recognizeText(in pixelBuffer: CVPixelBuffer) throws -> [IdTextLine]
}

final class IdTextRecognitionRepository: IdTextRecognitionRepositoryProtocol {

    static let shared = IdTextRecognitionRepository()

    private init() {}

    // Correction is trained on prose and mangles surnames — exactly the words
    // that matter here — so language correction stays off.
    private let request: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        return request
    }()

    func recognizeText(in pixelBuffer: CVPixelBuffer) throws -> [IdTextLine] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }

        let frameHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision reports boxes normalized 0–1; the parser's prominence
            // tier and the ported tests both speak pixels.
            let heightPx = Int(observation.boundingBox.height * frameHeight)
            return IdTextLine(candidate.string, heightPx)
        }
    }
}
