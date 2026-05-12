//
//  UpdateTerminalResponse.swift
//  PillCounter
//

import Foundation

struct UpdateTerminalResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
    }
}
