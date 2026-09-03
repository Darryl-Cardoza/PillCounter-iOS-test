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

/// Parses barcode formats supplied as a raw named-group regex
/// (e.g. `^(?<rxnumber>[^|]{1,32})\|(?<refillno>\d{1,3})\|(?<ndc>\d{11})\|(?<qty>[\d.]{1,10})\|(?<bucket>[^|]{1,16})$`)
/// against a scanned pipe-delimited value. The server's pattern is trusted and matched exactly —
/// optionality of any field (refillno, bucket, etc.) is whatever the server's regex encodes,
/// never overridden here.
enum BarcodeFormatParser {

    /// Maps the regex's named capture groups (server-defined, lowercase) to the app's field keys.
    static let groupNameToKey: [String: String] = [
        "rxnumber": "RXNO",
        "ndc":      "NDCNO",
        "refillno": "REFILLNO",
        "qty":      "QTY",
        "bucket":   "BUCKET"
    ]

    /// Keys whose captured value has "-" stripped before use (e.g. NDC `11-1134-33` → `1113433`).
    static let dashStrippedKeys: Set<String> = ["NDCNO"]

    // MARK: Regex Compilation

    /// Relaxes the `ndc` group's body to also accept "-" (e.g. scanned `0527-8113-37`),
    /// since the server's pattern (e.g. `\d{11}`) only allows bare digits. The dash is
    /// stripped from the captured value afterward via `dashStrippedKeys`.
    static func applyDashTolerance(to format: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\(\\?<ndc>([^()]*)\\)") else { return format }
        let range = NSRange(format.startIndex..., in: format)
        guard let match = regex.firstMatch(in: format, range: range),
              let fullRange = Range(match.range, in: format),
              let bodyRange = Range(match.range(at: 1), in: format) else { return format }

        var body = String(format[bodyRange]).replacingOccurrences(of: "\\d", with: "[\\d-]")
        // Widen the length quantifier by 2 to allow for up to two "-" separators (e.g. 11-1134-33).
        if let quantifierRegex = try? NSRegularExpression(pattern: "\\{(\\d+)\\}") {
            let bodyRange = NSRange(body.startIndex..., in: body)
            if let quantifierMatch = quantifierRegex.firstMatch(in: body, range: bodyRange),
               let numberRange = Range(quantifierMatch.range(at: 1), in: body),
               let count = Int(body[numberRange]),
               let matchRange = Range(quantifierMatch.range, in: body) {
                body.replaceSubrange(matchRange, with: "{\(count),\(count + 2)}")
            }
        }
        var result = format
        result.replaceSubrange(fullRange, with: "(?<ndc>\(body))")
        return result
    }

    private static func compile(_ format: String) throws -> NSRegularExpression {
        try NSRegularExpression(pattern: applyDashTolerance(to: format))
    }

    /// Maps a scanned barcode value against the server-supplied named-group regex format.
    /// Returns `[:]` if the format doesn't compile or the value doesn't match.
    static func mappedData(format: String, actualValue: String) throws -> [String: String] {
        guard !format.isEmpty, !actualValue.isEmpty else {
            print("[BarcodeFormatParser] mappedData: empty format or value — format=\(format) value=\(actualValue)")
            return [:]
        }

        let regex = try compile(format)
        let valueRange = NSRange(actualValue.startIndex..., in: actualValue)
        guard let match = regex.firstMatch(in: actualValue, range: valueRange) else {
            print("[BarcodeFormatParser] mappedData: NO MATCH")
            print("[BarcodeFormatParser]   format=\(format)")
            print("[BarcodeFormatParser]   value=\(actualValue)")
            return [:]
        }

        var result: [String: String] = [:]
        for (groupName, key) in groupNameToKey {
            let groupRange = match.range(withName: groupName)
            guard groupRange.location != NSNotFound,
                  let range = Range(groupRange, in: actualValue) else { continue }

            var value = String(actualValue[range]).trimmingCharacters(in: .whitespaces)
            if dashStrippedKeys.contains(key) {
                value = value.replacingOccurrences(of: "-", with: "")
            }
            result[key] = value
        }
        return result
    }

    // MARK: Barcode Format Match Check

    /// Compiles the server-supplied regex format and tests the scanned value against it.
    static func matches(_ value: String, format: String) -> Bool {
        guard !format.isEmpty else {
            print("[BarcodeFormatParser] matches: format empty — scanned value=\(value)")
            return false
        }

        do {
            let regex = try compile(format)
            let valueRange = NSRange(value.startIndex..., in: value)
            let isMatch = regex.firstMatch(in: value, range: valueRange) != nil
            if !isMatch {
                print("[BarcodeFormatParser] matches: NO MATCH")
                print("[BarcodeFormatParser]   format=\(format)")
                print("[BarcodeFormatParser]   value=\(value)")
            }
            return isMatch

        } catch {
            print("[BarcodeFormatParser] matches error: \(error) format=\(format)")
            return false
        }
    }
}
