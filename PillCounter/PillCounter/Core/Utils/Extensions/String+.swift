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
}
