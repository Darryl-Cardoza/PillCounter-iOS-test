//
//  IdNameParser.swift
//  PillCounter
//
//  Pure, dependency-free, deterministic. Direct port of IdNameParser.kt
//  (Android reference) — see plans/face-auth/ocr/ID_SCAN_OCR_IMPLEMENTATION.md
//  §5. Four tiers, first non-nil wins: labeledName, nameLabeledName,
//  commaName, prominentName.
//
//  Vocabulary distinction is load-bearing:
//  - STRIPPED_TOKENS are removed from a line, the rest is still evaluated.
//  - EXCLUDED_WORDS disqualify the entire line.
//

import Foundation

enum IdNameParser {

    private static let lastNameLabel = try! NSRegularExpression(
        pattern: #"^(?:LN|1)[:.]?\s+(.+)$"#, options: [.caseInsensitive]
    )
    private static let firstNameLabel = try! NSRegularExpression(
        pattern: #"^(?:FN|2)[:.]?\s+(.+)$"#, options: [.caseInsensitive]
    )
    private static let firstLabelLine = try! NSRegularExpression(
        pattern: #"^FIRST\s*NAME\b[:.]?\s*(.*)$"#, options: [.caseInsensitive]
    )
    private static let lastLabelLine = try! NSRegularExpression(
        pattern: #"^LAST\s*NAME\b[:.]?\s*(.*)$"#, options: [.caseInsensitive]
    )
    private static let fullNameLabelLine = try! NSRegularExpression(
        pattern: #"^(?:FULL\s*)?NAME\b[:.]?\s*(.*)$"#, options: [.caseInsensitive]
    )

    // ASCII only, matching Android. Widen to `\p{L}` for accented names if
    // this ever needs non-English deployments (Android parity, not applied).
    // Both apostrophe forms kept — Vision emits the typographic '’' too.
    private static let nameWord = try! NSRegularExpression(
        pattern: #"^[A-Za-z][A-Za-z'’-]*$"#
    )

    private static let whitespace = try! NSRegularExpression(pattern: #"\s+"#)

    /// Titles/credentials that may surround a name without disqualifying the line.
    private static let strippedTokens: Set<String> = [
        "DR", "MR", "MRS", "MS", "MISS", "PROF",
        "RPH", "PHARMD", "PHD", "MD", "RN", "JR", "SR", "II", "III", "IV",
    ]

    /// Vocabulary that marks a line as NOT a person's name.
    private static let excludedWords: Set<String> = [
        "PHARMACIST", "PHARMACY", "TECHNICIAN", "TECH", "INTERN", "NURSE", "DOCTOR",
        "MEDICAL", "CENTER", "CENTRE", "HOSPITAL", "CLINIC", "HEALTH", "HEALTHCARE",
        "CARE", "STAFF", "EMPLOYEE", "BADGE", "DEPARTMENT", "DEPT", "ID",
        "DRIVER", "DRIVERS", "LICENSE", "LICENCE", "IDENTIFICATION", "PERMIT", "CARD",
        "STATE", "USA", "CLASS", "DOB", "EXP", "ISS", "SEX", "HGT", "WGT", "EYES",
        "HAIR", "DONOR", "VETERAN", "ORGAN", "RESTRICTIONS", "ENDORSEMENTS", "REV",
        "NAME", "FIRST", "LAST", "MIDDLE", "OF", "THE", "AND",
        "STREET", "AVENUE", "ROAD", "DRIVE", "LANE", "BLVD", "APT", "ST", "AVE", "RD",
    ]

    static let maxSuggestions = 8

    static func parse(_ lines: [IdTextLine]) -> IdCardName? {
        let cleaned = cleanedLines(lines)
        if cleaned.isEmpty { return nil }

        return labeledName(cleaned)
            ?? nameLabeledName(cleaned)
            ?? commaName(cleaned)
            ?? prominentName(cleaned)
    }

    /// Every name-like word on the card, most prominent line first — shown to
    /// the user as tap-to-fill suggestions when `parse`'s single best guess
    /// may be wrong. Looser than `parse`: any line of up to 4 clean words
    /// contributes, so multi-part names aren't dropped.
    static func candidateWords(_ lines: [IdTextLine]) -> [String] {
        let cleaned = cleanedLines(lines)

        let labeled = nameLabelValues(cleaned).flatMap { suggestionWords($0) }
        let byProminence = cleaned
            .sorted { $0.heightPx > $1.heightPx }
            .flatMap { suggestionWords($0.text) }

        return orderedDedupe(labeled + byProminence).prefix(maxSuggestions).map { $0 }
    }

    // MARK: - Shared helpers

    private static func cleanedLines(_ lines: [IdTextLine]) -> [IdTextLine] {
        lines
            .map { IdTextLine($0.text.trimmingCharacters(in: .whitespacesAndNewlines), $0.heightPx) }
            .filter { !$0.text.isEmpty }
    }

    /// Ordered dedupe — Swift has no `distinct()`; a plain `Set` would lose
    /// the ranking that is the whole point of `candidateWords`.
    private static func orderedDedupe(_ words: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in words where !seen.contains(word) {
            seen.insert(word)
            result.append(word)
        }
        return result
    }

    private static func splitWhitespace(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
        guard let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range])
    }

    /// Name-like words from one line, or empty if the line can't be part of a
    /// name (too long, digits, or role/org/license vocabulary anywhere in it).
    private static func suggestionWords(_ text: String) -> [String] {
        let words = splitWhitespace(text)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,")) }
            .filter { !$0.isEmpty && !strippedTokens.contains($0.uppercased()) }
        if words.count > 4 { return [] }
        if words.contains(where: { matches(nameWord, $0) == nil || excludedWords.contains($0.uppercased()) }) {
            return []
        }
        return words.filter { $0.count >= 2 }.map(displayCase)
    }

    /// "COLE" → "Cole", "O'BRIEN" → "O'Brien", "SMITH-JONES" → "Smith-Jones".
    static func displayCase(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = ""
        var capitalizeNext = true
        for c in lower {
            if capitalizeNext, c.isLetter {
                result.append(Character(c.uppercased()))
            } else {
                result.append(c)
            }
            capitalizeNext = !c.isLetter
        }
        return result
    }

    // MARK: - Tier 1: labeledName

    private static func labeledName(_ lines: [IdTextLine]) -> IdCardName? {
        var last: String?
        var first: String?
        for line in lines {
            if last == nil, let m = matches(lastNameLabel, line.text) {
                let value = group(m, 1, in: line.text)
                if isNameText(value) { last = value }
            }
        }
        for line in lines {
            if first == nil, let m = matches(firstNameLabel, line.text) {
                let value = group(m, 1, in: line.text)
                if isNameText(value) { first = value }
            }
        }
        guard let last, let first else { return nil }
        // The FN value may carry a middle name ("JOHN A") — keep only the first word.
        guard let firstWord = splitWhitespace(first).first else { return nil }
        return IdCardName(firstName: displayCase(firstWord), lastName: displayCase(last))
    }

    // MARK: - Tier 2: nameLabeledName

    /// A printed name label anywhere on the card: "Name: Cole Paulson" inline,
    /// a bare "Name" whose value is the NEXT line, or stacked "First Name" /
    /// "Last Name" labels each with an inline or next-line value.
    private static func nameLabeledName(_ lines: [IdTextLine]) -> IdCardName? {
        var first: String?
        var last: String?
        var full: String?

        for (index, line) in lines.enumerated() {
            let firstMatch = matches(firstLabelLine, line.text)
            let lastMatch = matches(lastLabelLine, line.text)
            // FULL anchors at "NAME…", so it can't also match a FIRST/LAST label line.
            let fullMatch: NSTextCheckingResult? =
                (firstMatch == nil && lastMatch == nil) ? matches(fullNameLabelLine, line.text) : nil

            if let firstMatch, first == nil {
                let value = labelValue(lines, index, group(firstMatch, 1, in: line.text))
                if let value, isNameText(value) { first = value }
            } else if let lastMatch, last == nil {
                let value = labelValue(lines, index, group(lastMatch, 1, in: line.text))
                if let value, isNameText(value) { last = value }
            } else if let fullMatch, full == nil {
                full = labelValue(lines, index, group(fullMatch, 1, in: line.text))
            }
        }

        if let first, let last {
            guard let firstWord = splitWhitespace(first).first else { return nil }
            return IdCardName(firstName: displayCase(firstWord), lastName: displayCase(last))
        }

        guard let full else { return nil }
        return commaNameFromText(full) ?? multiWordName(full)
    }

    /// Values adjacent to any printed name label, for suggestion ranking.
    private static func nameLabelValues(_ lines: [IdTextLine]) -> [String] {
        var results: [String] = []
        for (index, line) in lines.enumerated() {
            let match = matches(firstLabelLine, line.text)
                ?? matches(lastLabelLine, line.text)
                ?? matches(fullNameLabelLine, line.text)
            guard let match else { continue }
            if let value = labelValue(lines, index, group(match, 1, in: line.text)) {
                results.append(value)
            }
        }
        return results
    }

    /// Inline remainder of a label line, or the following line when the label stands alone.
    private static func labelValue(_ lines: [IdTextLine], _ index: Int, _ inline: String) -> String? {
        let trimmedInline = inline.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmedInline.isEmpty
            ? (index + 1 < lines.count ? lines[index + 1].text.trimmingCharacters(in: .whitespacesAndNewlines) : "")
            : trimmedInline
        return value.isEmpty ? nil : value
    }

    // MARK: - Tier 3: commaName

    private static func commaName(_ lines: [IdTextLine]) -> IdCardName? {
        for line in lines {
            if let name = commaNameFromText(line.text) { return name }
        }
        return nil
    }

    private static func commaNameFromText(_ text: String) -> IdCardName? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let lastPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let firstPart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNameText(lastPart), isNameText(firstPart) else { return nil }
        // The first-name side may carry a middle name/initial — keep the first word.
        guard let firstWord = splitWhitespace(firstPart).first else { return nil }
        guard firstWord.count >= 2, lastPart.count >= 2 else { return nil }
        return IdCardName(firstName: displayCase(firstWord), lastName: displayCase(lastPart))
    }

    /// Lenient first+last extraction for a value that a name label vouches for:
    /// up to 4 clean words, first word → first name, last word → last name.
    private static func multiWordName(_ text: String) -> IdCardName? {
        let words = splitWhitespace(text)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,")) }
            .filter { !$0.isEmpty && !strippedTokens.contains($0.uppercased()) }
        guard (2...4).contains(words.count) else { return nil }
        if words.contains(where: { matches(nameWord, $0) == nil || excludedWords.contains($0.uppercased()) }) {
            return nil
        }
        guard let first = words.first, let last = words.last, first.count >= 2, last.count >= 2 else { return nil }
        return IdCardName(firstName: displayCase(first), lastName: displayCase(last))
    }

    // MARK: - Tier 4: prominentName

    private static func prominentName(_ lines: [IdTextLine]) -> IdCardName? {
        var best: (line: IdTextLine, words: [String])?
        for line in lines {
            guard let words = nameWords(line.text) else { continue }
            if best == nil || line.heightPx > best!.line.heightPx {
                best = (line, words)
            }
        }
        guard let best, let first = best.words.first, let last = best.words.last else { return nil }
        return IdCardName(firstName: displayCase(first), lastName: displayCase(last))
    }

    /// Tokenizes a line and returns its 2–3 name words (titles/credentials
    /// stripped, single-letter middle initial allowed), or nil if the line
    /// can't be a person's name.
    private static func nameWords(_ text: String) -> [String]? {
        let words = splitWhitespace(text)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,")) }
            .filter { !$0.isEmpty && !strippedTokens.contains($0.uppercased()) }
        guard (2...3).contains(words.count) else { return nil }
        if words.contains(where: { matches(nameWord, $0) == nil || excludedWords.contains($0.uppercased()) }) {
            return nil
        }
        // First and last words must be real names; only a middle token may be an initial.
        guard let first = words.first, let last = words.last, first.count >= 2, last.count >= 2 else { return nil }
        return words
    }

    private static func isNameText(_ text: String) -> Bool {
        let words = splitWhitespace(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !words.isEmpty else { return false }
        return words.allSatisfy { matches(nameWord, $0) != nil && !excludedWords.contains($0.uppercased()) }
    }
}
