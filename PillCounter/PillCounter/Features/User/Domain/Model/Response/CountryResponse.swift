//
//  CountryResponse.swift
//  PillCounter
//

import Foundation

struct CountryResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: CountryData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct CountryData: Codable {
    let countries: [Country]?
}

struct Country: Codable, Identifiable, Hashable, CodeNameOption {
    let code: String
    let name: String
    let states: [StateItem]?

    var id: String { code }
}

struct StateItem: Codable, Identifiable, Hashable, CodeNameOption {
    let code: String
    let name: String

    var id: String { code }
}
