//
//  VerifyOTPResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct VerifyOTPResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: VerifyOTPData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct VerifyOTPData: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: VerifyOTPUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct VerifyOTPUser: Codable {
    let userId: String?
    let email: String?
    let isVerified: Bool?
    let role: VerifyOTPRole?
    let authIsLocked: Bool?
    let isPmsIntegrated: Bool?
    let allowLocalStorage: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case isVerified = "is_verified"
        case role
        case authIsLocked = "auth_is_locked"
        case isPmsIntegrated = "is_pms_integrated"
        case allowLocalStorage = "allow_local_storage"
    }
}

struct VerifyOTPRole: Codable {
    let id: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}
