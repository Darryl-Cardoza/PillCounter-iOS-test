//
//  String+.swift
//  PillCounter
//
//  Created by HC on 29/12/25.
//

extension String {
    /// Compares semantic version strings (e.g. "1.2.10" vs "1.3.0")
    func isVersionGreater(than other: String) -> Bool {
        let lhs = self.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = other.split(separator: ".").map { Int($0) ?? 0 }

        let maxLength = max(lhs.count, rhs.count)

        for i in 0..<maxLength {
            let left = i < lhs.count ? lhs[i] : 0
            let right = i < rhs.count ? rhs[i] : 0

            if left != right {
                return left > right
            }
        }
        return false
    }

    /// Normalizes an NDC to the 11-digit HIPAA 5-4-2 format so a PMS-sent NDC
    /// in any of the three FDA-valid hyphenated layouts (4-4-2, 5-3-2, 5-4-1 —
    /// all 10 digits) matches a row stored in a different one of those layouts.
    /// Segment boundaries come from the hyphens, so this only fixes the
    /// 10-vs-11-digit mismatch when the source string is hyphenated; a bare
    /// (no-hyphen) 10-digit NDC has no way to know which segment is short, so
    /// it's returned unchanged (digits-only comparison still catches the
    /// hyphen-only formatting difference, just not the padding one).
    var ndcNormalized: String {
        let segments = self.split(separator: "-", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            return self.filter(\.isNumber)
        }

        let padded: [String] = zip(segments, [5, 4, 2]).map { segment, width in
            let digits = segment.filter(\.isNumber)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }

        return padded.joined()
    }
}
