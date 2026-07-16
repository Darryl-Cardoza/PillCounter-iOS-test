//
//  PharmacyTypeResponse.swift
//  PillCounter
//

import Foundation

struct PharmacyTypeResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: PharmacyTypeData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct PharmacyTypeData: Codable {
    let pharmacyTypes: [PharmacyTypeOption]?

    enum CodingKeys: String, CodingKey {
        case pharmacyTypes = "pharmacy_types"
    }
}

struct PharmacyTypeOption: Codable, Identifiable, Equatable {
    let code: String
    let label: String

    var id: String { code }
}
