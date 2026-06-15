//
//  SendOTPResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct SendOTPResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: OTPData?

    // Custom CodingKeys to match JSON keys like `is_success`
    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct OTPData: Codable {
    let email: String?
    let isNewUser: Bool?
    let expiresIn: Int?
    let sentCount: Int?
    let rateLimitRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case email
        case isNewUser = "is_new_user"
        case expiresIn = "expires_in"
        case sentCount = "sent_count"
        case rateLimitRemaining = "rate_limit_remaining"
    }
}
