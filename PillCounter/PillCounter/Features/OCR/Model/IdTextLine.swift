//
//  IdTextLine.swift
//  PillCounter
//
//  Ported from IdNameParser.kt (Android reference) — see
//  plans/face-auth/ocr/ID_SCAN_OCR_IMPLEMENTATION.md §5.4.
//

import Foundation

/// A single OCR line with its glyph height, used to rank prominence on the card.
struct IdTextLine: Equatable {
    let text: String
    /// Pixel height of the OCR line's bounding box. Load-bearing: the badge
    /// tier assumes the person's name is the largest text on the card.
    let heightPx: Int

    init(_ text: String, _ heightPx: Int = 0) {
        self.text = text
        self.heightPx = heightPx
    }
}

/// Name extracted from a photo ID (driver's license or staff badge).
struct IdCardName: Equatable {
    let firstName: String
    let lastName: String
}

/// Result of analyzing a single confirmed frame (or barcode payload).
struct IdScanResult: Equatable {
    /// nil when no confident pair was found — the chips carry the load.
    let name: IdCardName?
    let suggestions: [String]
}
