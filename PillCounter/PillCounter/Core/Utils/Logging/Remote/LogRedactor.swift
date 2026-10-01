import Foundation

/// Masks structurally-detectable sensitive patterns in free-text log fields
/// before they leave the device. THIS IS A SAFETY NET, NOT A GUARANTEE: a
/// patient/user name or other free-form sensitive detail typed directly into a
/// log message as plain text is indistinguishable from ordinary text and will
/// NOT be caught here. Only what is shipped remotely (message, error, context) is
/// redacted; the DEBUG console output is not.
public enum LogRedactor {
    public static func redact(_ text: String?) -> String? {
        guard let text else { return nil }
        var result = text
        result = replacing(result, pattern: emailPattern, with: "[REDACTED_EMAIL]")
        result = replacing(result, pattern: nationalIdPattern, with: "[REDACTED_ID]")
        result = redactLuhnValidCardNumbers(result)
        result = replacing(result, pattern: phonePattern, with: "[REDACTED_PHONE]")
        return result
    }

    private static let emailPattern = #"[\w.+-]+@[\w-]+\.[\w.-]+"#
    private static let nationalIdPattern = #"\b\d{3}-\d{2}-\d{4}\b"#
    // Requires a separator (space/dash/dot/plus/parens) inside the run so a bare
    // contiguous digit run — an NDC code, Rx number, order/batch ID — never matches.
    private static let phonePattern = #"(?<![\d.])(?:\+\d{1,3}[\s.-]?)?\(?\d{2,4}\)?[\s.-]\d{3,4}[\s.-]\d{3,4}(?!\.?\d)"#
    // 13-19 digits, optionally grouped with spaces/dashes; Luhn-checked separately
    // below rather than matched-and-replaced in one pass, since only a Luhn-valid
    // run should be treated as a real card number.
    private static let cardCandidatePattern = #"\b(?:\d[ -]?){13,19}\b"#

    private static func redactLuhnValidCardNumbers(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: cardCandidatePattern) else { return text }
        let nsText = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            let candidate = nsText.substring(with: match.range)
            let digitsOnly = candidate.filter(\.isNumber)
            guard isLuhnValid(digitsOnly) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: "[REDACTED_CARD]")
        }
        return result
    }

    private static func isLuhnValid(_ digits: String) -> Bool {
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        var alternate = false
        for char in digits.reversed() {
            guard var digit = char.wholeNumberValue else { return false }
            if alternate {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
            alternate.toggle()
        }
        return sum % 10 == 0
    }

    private static func replacing(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
