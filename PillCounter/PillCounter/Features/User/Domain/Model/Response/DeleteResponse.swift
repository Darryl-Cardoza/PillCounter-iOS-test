//
//  DeleteUserResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct DeleteUserResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: DeleteUserData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct DeleteUserData: Codable {
    let userId: String?
    let deleted: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case deleted
    }
}

