//
//  CountryResponse.swift
//  PillCounter
//

import Foundation

struct CountryResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let data: CountryData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case data
    }
}

struct CountryData: Codable {
    let countries: [CountryOption]?
}

struct CountryOption: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let states: [StateOption]?

    var id: String { code }
}

struct StateOption: Codable, Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
}
