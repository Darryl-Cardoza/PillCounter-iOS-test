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
            pattern: "(?:\\(01\\)|01)(\\d{8,14})"
        ),
        "LotNumber": try! NSRegularExpression(
            pattern: "(?:\\(10\\)|10)([\\w\\d/\\-\\.]{1,20}?)(?=\\(\\d{2,4}\\)|\\x1D|$)"
        ),
        "SerialNumber": try! NSRegularExpression(
            pattern: "(?:\\(21\\)|21)([\\w\\d/\\-\\.]{1,20}?)(?=\\(\\d{2,4}\\)|\\x1D|$)"
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
        // 1️⃣ Detect plain numeric barcodes (EAN-8, EAN-13, UPC-A, ITF-14)
        // These do NOT contain GS1 AIs like (01)
        if raw.range(of: #"^\d{8,14}$"#, options: .regularExpression) != nil {
            let gtin14 = normalizeGTIN14(raw)
            let result = GS1BarcodeData(gtin: gtin14)
            return result
        }

        // 2️⃣ Remove prefixes like ]C1, ]J1, etc.
        let cleaned = raw.replacingOccurrences(
            of: #"\](?i)(c1|j1|q3|e0|d2)"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(of: "\u{001D}", with: "") // GS (FNC1) separator if present

        var result = GS1BarcodeData()

        // 3️⃣ Extract simple string fields
        let rawGTIN = extract("GTIN", from: cleaned)
        result.gtin = normalizeGTIN14(rawGTIN)
        result.lotNumber = extract("LotNumber", from: cleaned)
        result.serialNumber = extract("SerialNumber", from: cleaned)

        // 4️⃣ Extract dates
        result.productionDate = extractDate("ProductionDate", from: cleaned)
        result.packingDate = extractDate("PackingDate", from: cleaned)
        result.sellByDate = extractDate("SellByDate", from: cleaned)
        result.expirationDate = extractDate("ExpirationDate", from: cleaned)

        // 5️⃣ Extract weights
        result.netWeightKg = extractWeight("NetWeightKgs", from: cleaned)
        result.grossWeightKg = extractWeight("GrossWeightKgs", from: cleaned)
        result.netWeightLb = extractWeight("NetWeightPounds", from: cleaned)
        result.grossWeightLb = extractWeight("GrossWeightPounds", from: cleaned)

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
    
    private func normalizeGTIN14(_ gtin: String?) -> String? {
        guard let gtin = gtin else { return nil }
        if gtin.count == 14 { return gtin }
        if gtin.count < 14 { return String(repeating: "0", count: 14 - gtin.count) + gtin }
        return gtin
    }
}
