//
//  BarcodeAndQRDecoder.swift
//  PillCounter
//
//  Created by HC on 14/11/25.
//

import Foundation

// MARK: - Output Model (same structure as Android version)
struct GS1BarcodeData {
    var gtin: String?
    var lotNumber: String?
    var serialNumber: String?
    var productionDate: Date?
    var packingDate: Date?
    var sellByDate: Date?
    var expirationDate: Date?
    var netWeightKg: Double?
    var grossWeightKg: Double?
    var netWeightLb: Double?
    var grossWeightLb: Double?
}

// MARK: - GS1 Decoder Class
class BarcodeAndQRDecoder: ObservableObject {

    // MARK: GS1 Patterns (Same as your Android Regex patterns)
    private let regexPatterns: [String: NSRegularExpression] = [
        "GTIN": try! NSRegularExpression(
            pattern: "(?:\\(01\\)|01)(\\d{14})"
        ),
        "LotNumber": try! NSRegularExpression(
            pattern: "(?:\\(10\\)|(?<=\\x1D)10|(?<=\\d{18})10)([\\w\\d/\\-\\.]{1,20})(?=\\(\\d{2,4}\\)|\\x1D|$)"
        ),
        "SerialNumber": try! NSRegularExpression(
            pattern: "(?:\\(21\\)|21)([\\w\\d/\\-\\.]{1,20})(?=\\(\\d{2,4}\\)|\\x1D|$)"
        ),
        "ProductionDate": try! NSRegularExpression(
            pattern: "(?:\\(11\\)|11)(\\d{6})"),
        "PackingDate": try! NSRegularExpression(
            pattern: "(?:\\(13\\)|13)(\\d{6})"),
        "SellByDate": try! NSRegularExpression(
            pattern: "(?:\\(15\\)|15)(\\d{6})"),
        "ExpirationDate": try! NSRegularExpression(
            pattern: "(?:\\(17\\)|17)(\\d{6})"),

        "NetWeightKgs": try! NSRegularExpression(
            pattern: "(?:\\(310[0-4]\\)|310[0-4])(\\d{6})"),
        "GrossWeightKgs": try! NSRegularExpression(
            pattern: "(?:\\(330[0-4]\\)|330[0-4])(\\d{6})"),
        "NetWeightPounds": try! NSRegularExpression(
            pattern: "(?:\\(320[0-4]\\)|320[0-4])(\\d{6})"),
        "GrossWeightPounds": try! NSRegularExpression(
            pattern: "(?:\\(340[0-4]\\)|340[0-4])(\\d{6})"),
    ]

    // MARK: - Public Decode Function
    /**
     Decodes a raw GS1 barcode string into structured GS1BarcodeData.

     - Parameter raw: The original scanned QR or barcode string.
     - Returns: A GS1BarcodeData object with all extracted fields.
     */
    func decode(_ raw: String) -> GS1BarcodeData {
        // A plain digit-only scan (UPC-A/EAN-13/NDC linear barcode, no GS1 envelope)
        // is NOT itself a valid GTIN unless it is already exactly 14 digits — a
        // 13-digit EAN-13/UPC value must be left-padded with a single "0" to form
        // a real GTIN-14, or it will never match the 14-digit GTIN a GS1
        // DataMatrix/QR decode produces for the same physical product on rescan.
        if raw.range(of: #"^\d{8,14}$"#, options: .regularExpression) != nil {
            let gtin14 = raw.count < 14 ? String(repeating: "0", count: 14 - raw.count) + raw : raw
            return GS1BarcodeData(gtin: gtin14)
        }

        // Remove symbology prefix only
        let stripped = raw.replacingOccurrences(
            of: #"\](?i)(c1|j1|q3|e0|d2)"#,
            with: "",
            options: .regularExpression
        )

        // ✅ Parse GS1 properly using a left-to-right AI walker
        let fields = parseGS1Fields(stripped)

        var result = GS1BarcodeData()
        result.gtin           = fields["01"]
        result.lotNumber      = fields["10"]
        result.serialNumber   = fields["21"]
        result.productionDate = parseDate(fields["11"])
        result.packingDate    = parseDate(fields["13"])
        result.sellByDate     = parseDate(fields["15"])
        result.expirationDate = parseDate(fields["17"])
        result.netWeightKg    = parseWeight(fields["3100"], decimals: 0)
                             ?? parseWeight(fields["3101"], decimals: 1)
                             ?? parseWeight(fields["3102"], decimals: 2)
                             ?? parseWeight(fields["3103"], decimals: 3)
                             ?? parseWeight(fields["3104"], decimals: 4)
        result.grossWeightKg  = parseWeight(fields["3300"], decimals: 0)
                             ?? parseWeight(fields["3301"], decimals: 1)
                             ?? parseWeight(fields["3302"], decimals: 2)
                             ?? parseWeight(fields["3303"], decimals: 3)
                             ?? parseWeight(fields["3304"], decimals: 4)
        result.netWeightLb    = parseWeight(fields["3200"], decimals: 0)
                             ?? parseWeight(fields["3201"], decimals: 1)
                             ?? parseWeight(fields["3202"], decimals: 2)
                             ?? parseWeight(fields["3203"], decimals: 3)
                             ?? parseWeight(fields["3204"], decimals: 4)
        result.grossWeightLb  = parseWeight(fields["3400"], decimals: 0)
                             ?? parseWeight(fields["3401"], decimals: 1)
                             ?? parseWeight(fields["3402"], decimals: 2)
                             ?? parseWeight(fields["3403"], decimals: 3)
                             ?? parseWeight(fields["3404"], decimals: 4)
        return result
    }

    // MARK: - Core GS1 left-to-right field parser
    /// Walks the barcode string position by position, extracting AI → value pairs.
    /// Handles both parenthesis format (01)XXXX and raw format 01XXXX\x1D
    private func parseGS1Fields(_ input: String) -> [String: String] {
        var fields: [String: String] = [:]

        // Known fixed-length AIs: AI → value length (digits only, not counting AI)
        let fixedLength: [String: Int] = [
            "00": 18, "01": 14, "02": 14,
            "11": 6,  "12": 6,  "13": 6,  "15": 6,  "16": 6,  "17": 6,
            "3100": 6, "3101": 6, "3102": 6, "3103": 6, "3104": 6,
            "3200": 6, "3201": 6, "3202": 6, "3203": 6, "3204": 6,
            "3300": 6, "3301": 6, "3302": 6, "3303": 6, "3304": 6,
            "3400": 6, "3401": 6, "3402": 6, "3403": 6, "3404": 6,
        ]

        let chars = Array(input)
        var i = 0

        while i < chars.count {
            // Skip GS separators
            if chars[i] == "\u{001D}" { i += 1; continue }

            // Parenthesis format: (01)12345...
            if chars[i] == "(" {
                guard let closeIdx = chars[i...].firstIndex(of: ")") else { break }
                let aiStart = chars.index(after: i)
                let ai = String(chars[aiStart..<closeIdx])
                i = chars.index(after: closeIdx)

                if let valueLen = fixedLength[ai] {
                    let end = min(i + valueLen, chars.count)
                    fields[ai] = String(chars[i..<end])
                    i = end
                } else {
                    // Variable length: read until GS, next '(', or end
                    var end = i
                    while end < chars.count && chars[end] != "\u{001D}" && chars[end] != "(" {
                        end += 1
                    }
                    fields[ai] = String(chars[i..<end])
                    i = end
                }
                continue
            }

            // Raw format: try 4-digit AI first, then 3-digit, then 2-digit
            var matched = false
            for aiLen in [4, 3, 2] {
                guard i + aiLen <= chars.count else { continue }
                let ai = String(chars[i..<(i + aiLen)])
                guard ai.allSatisfy({ $0.isNumber }) else { continue }

                if let valueLen = fixedLength[ai] {
                    let valueStart = i + aiLen
                    let valueEnd = min(valueStart + valueLen, chars.count)
                    guard valueStart < chars.count else { continue }
                    fields[ai] = String(chars[valueStart..<valueEnd])
                    i = valueEnd
                    matched = true
                    break
                } else if aiLen == 2 {
                    // Variable-length 2-digit AI: read until GS or end
                    let valueStart = i + aiLen
                    var valueEnd = valueStart
                    while valueEnd < chars.count && chars[valueEnd] != "\u{001D}" {
                        valueEnd += 1
                    }
                    fields[ai] = String(chars[valueStart..<valueEnd])
                    i = valueEnd
                    matched = true
                    break
                }
            }

            if !matched { i += 1 }
        }

        return fields
    }

    // MARK: - Helpers
    private func parseDate(_ value: String?) -> Date? {
        guard let value, value.count == 6 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)
    }

    private func parseWeight(_ value: String?, decimals: Int) -> Double? {
        guard let value, let raw = Double(value) else { return nil }
        return raw / pow(10.0, Double(decimals))
    }
    // ✅ Inserts \x1D after known fixed-length AIs so variable fields parse correctly
    private func insertSeparatorsAfterFixedFields(_ input: String) -> String {
        // Fixed-length AIs and their total length (AI digits + value digits)
        // AI(01) = 2+14=16, AI(11/13/15/17) = 2+6=8, AI(310x) = 4+6=10
        let fixedPatterns: [(pattern: String, replacement: String)] = [
            // GTIN: (01) + 14 digits → insert \x1D after
            (#"((?:\(01\)|01)\d{14})"#,       "$1\u{001D}"),
            // Dates: (11)(13)(15)(17) + 6 digits
            (#"((?:\(1[1357]\)|1[1357])\d{6})"#, "$1\u{001D}"),
            // Weights: 310x/330x/320x/340x + 6 digits
            (#"((?:\(3[13][024][0-4]\)|3[13][024][0-4])\d{6})"#, "$1\u{001D}"),
        ]

        var result = input
        for (pattern, replacement) in fixedPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        // Collapse any double \x1D separators
        result = result.replacingOccurrences(of: "\u{001D}\u{001D}", with: "\u{001D}")
        return result
    }
    




    // MARK: - Extract string value for a GS1 Application Identifier
    /**
     Extracts the value for the given GS1 AI as a String.

     - Parameter key: The GS1 identifier key ("GTIN", "LotNumber", etc.)
     - Parameter barcode: The cleaned barcode string.
     - Returns: The extracted String value or nil.
     */
    private func extract(_ key: String, from barcode: String) -> String? {
        guard let regex = regexPatterns[key] else { return nil }

        let range = NSRange(barcode.startIndex..<barcode.endIndex, in: barcode)
        guard let match = regex.firstMatch(in: barcode, range: range),
            match.numberOfRanges > 1,
            let resultRange = Range(match.range(at: 1), in: barcode)
        else { return nil }

        return String(barcode[resultRange])
    }

    // MARK: - Extract Date (YYMMDD → Date)
    /**
     Parses a GS1 date (YYMMDD) into a Swift Date object.

     - Parameter key: GS1 identifier for date (e.g., "ExpirationDate")
     - Parameter barcode: Raw or cleaned barcode string.
     - Returns: Date object or nil.
     */
    private func extractDate(_ key: String, from barcode: String) -> Date? {
        guard let value = extract(key, from: barcode) else { return nil }
        guard value.count == 6 else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        return formatter.date(from: value)
    }

    // MARK: - Extract Weight (AI310x/330x/320x/340x)
    /**
     Extracts weight from GS1 weight AIs (e.g., 3103 → 3 decimal places).

     - Parameter key: Weight identifier ("NetWeightKgs", "GrossWeightLb", etc.)
     - Parameter barcode: The scanned barcode string.
     - Returns: The decoded weight as Double or nil.
     */
    private func extractWeight(_ key: String, from barcode: String) -> Double? {
        guard let regex = regexPatterns[key] else { return nil }

        let range = NSRange(barcode.startIndex..<barcode.endIndex, in: barcode)
        guard let match = regex.firstMatch(in: barcode, range: range) else {
            return nil
        }

        let fullMatch = (barcode as NSString).substring(with: match.range)
        let identifier = String(fullMatch.prefix(4))

        // Last digit indicates decimal places
        let decimals = Int(String(identifier.last!)) ?? 0

        guard match.numberOfRanges > 1 else { return nil }
        let rawDigits = (barcode as NSString).substring(
            with: match.range(at: 1))

        guard let intValue = Double(rawDigits) else { return nil }

        let divisor = pow(10.0, Double(decimals))
        return intValue / divisor
    }
    

}
