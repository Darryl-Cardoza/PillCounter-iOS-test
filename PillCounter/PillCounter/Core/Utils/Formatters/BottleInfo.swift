//
//  BottleInfo.swift
//  PillCounter
//

import Foundation

struct BottleInfo: Codable, Equatable {
    var lotNumber: String?
    var expirationDate: String?
    var serialNumber: String?
    var txnDetailsIds: [Int64] = []
    var scannedAt: Int64
}

extension Array where Element == BottleInfo {

    static func decode(from json: String?) -> [BottleInfo] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([BottleInfo].self, from: data)) ?? []
    }

    func encodedJson() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
