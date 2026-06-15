//
//  RefreshTokenResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct RefreshTokenResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: RefreshTokenData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct RefreshTokenData: Codable {
    let userId: String?
    let email: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
