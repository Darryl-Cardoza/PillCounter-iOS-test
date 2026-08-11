//
//  TerminalListResponse.swift
//  PillCounter
//

import Foundation

struct TerminalListResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let data: TerminalListData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case data
    }
}

struct TerminalListData: Codable {
    let terminals: [UserTerminal]?
}
