//
//  LogoutResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct LogoutResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
    }
}
