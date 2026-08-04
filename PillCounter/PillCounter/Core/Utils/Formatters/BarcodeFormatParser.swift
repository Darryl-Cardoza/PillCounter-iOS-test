//
//  BarcodeFormatParser.swift
//  PillCounter
//

import Foundation

// MARK: - ParsedScanData

struct ParsedScanData {
    let rxNo:     String?
    let ndcNo:    String?
    let drugName: String?
    let qty:      String?
    let refil:    String?
    let rawMap:   [String: String]

    init(
        rxNo:     String?           = nil,
        ndcNo:    String?           = nil,
        drugName: String?           = nil,
        qty:      String?           = nil,
        refil:    String?           = nil,
        rawMap:   [String: String]  = [:]
    ) {
        self.rxNo     = rxNo
        self.ndcNo    = ndcNo
        self.drugName = drugName
        self.qty      = qty
        self.refil    = refil
        self.rawMap   = rawMap
    }
}

// MARK: - BarcodeFormatParser

/// Parses `{KEY}`-templated barcode formats (e.g. `{RXNO}|{NDCNO}|{QTY}|{BUCKET}`)
/// against a scanned pipe-delimited value. Reusable across any feature that
/// needs to decode a configurable barcode layout, not just Rx scanning.
enum BarcodeFormatParser {

    /// Placeholder keys treated as optional when they're the last field in the format.
    /// Add new optional trailing fields here — no other change needed.
    static let optionalTrailingKeys: Set<String> = ["BUCKET", "REFILLNO"]

    // MARK: Extract Keys / Values

    static func extractKeys(from format: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "\\{(.*?)\\}")
        let range = NSRange(format.startIndex..., in: format)
        return regex.matches(in: format, range: range).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: format) else { return nil }
            return String(format[keyRange])
                .trimmingCharacters(in: .whitespaces)
                .uppercased()
        }
    }

    static func extractValues(from rawValue: String) -> [String] {
        rawValue
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Maps a scanned barcode value against a `{KEY}`-templated format string.
    /// Returns `[:]` if the format has no placeholders or the value has no segments.
    static func mappedData(format: String, actualValue: String) throws -> [String: String] {
        let keys   = try extractKeys(from: format)
        let values = extractValues(from: actualValue)

        guard !keys.isEmpty, !values.isEmpty else { return [:] }

        return zip(keys, values).reduce(into: [String: String]()) { result, pair in
            result[pair.0] = pair.1
        }
    }

    // MARK: Barcode Format Match Check

    /// Builds a regex from the configured format and tests the scanned value against it.
    static func matches(_ value: String, format: String) -> Bool {
        guard !format.isEmpty else { return false }

        do {
            let placeholderRegex = try NSRegularExpression(pattern: "\\{[^}]+\\}")
            let formatRange      = NSRange(format.startIndex..., in: format)
            let matches          = placeholderRegex.matches(in: format, range: formatRange)
            guard !matches.isEmpty else { return false }

            var regexParts: [String] = []
            var lastEnd = format.startIndex

            for (index, match) in matches.enumerated() {
                guard let matchRange = Range(match.range, in: format) else { continue }

                let literal = String(format[lastEnd..<matchRange.lowerBound])
                let keyName = String(format[matchRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                    .uppercased()

                let isLastPlaceholder = index == matches.count - 1
                let isOptional        = isLastPlaceholder && optionalTrailingKeys.contains(keyName)

                if isOptional {
                    let escapedLiteral = NSRegularExpression.escapedPattern(for: literal)
                    regexParts.append("(?:\(escapedLiteral)(.+?))?")
                } else {
                    if !literal.isEmpty {
                        regexParts.append(NSRegularExpression.escapedPattern(for: literal))
                    }
                    regexParts.append("(.+?)")
                }

                lastEnd = matchRange.upperBound
            }

            let trailing = String(format[lastEnd...])
            if !trailing.isEmpty {
                regexParts.append(NSRegularExpression.escapedPattern(for: trailing))
            }

            let pattern    = "^" + regexParts.joined() + "$"
            let valueRegex = try NSRegularExpression(pattern: pattern)
            let valueRange = NSRange(value.startIndex..., in: value)
            return valueRegex.firstMatch(in: value, range: valueRange) != nil

        } catch {
            print("[BarcodeFormatParser] matches error: \(error)")
            return false
        }
    }
}
