//
//  UserResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct UserResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: UserData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

// MARK: - Data
struct UserData: Codable {
    /// Some APIs wrap data inside `user`, others expose profile/settings directly.
    let user: UserDetails?
    let profile: UserProfile?
    let settings: UserSettings?
}

// MARK: - UserDetails
struct UserDetails: Codable {
    let userId: String?
    let isVerified: Bool?
    let createdAt: String?
    let updatedAt: String?
    let profile: UserProfile?
    let settings: UserSettings?
    let auth: UserAuth?
    let role: UserRole?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isVerified = "is_verified"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case profile
        case settings
        case auth
        case role
    }
}

// MARK: - Profile
struct UserProfile: Codable {
    let fname: String?
    let lname: String?
    let email: String?
    let phoneNumber: String?
    let avatarURL: String?
    let isProfileCompleted: Bool?
    let pharmacyName: String?
    let npiID: String?
    let isVerified: Bool?
    let isHl7Enabled: Bool?
    let bucket: [String]
    let role: UserRole?
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case fname = "fname"
        case lname = "lname"
        case email
        case phoneNumber = "phone_number"
        case avatarURL = "avatar_url"
        case isProfileCompleted = "is_profile_completed"
        case pharmacyName = "pharmacy_name"
        case npiID = "npi_id"
        case isVerified = "is_verified"
        case isHl7Enabled =  "is_hl7_enabled"
        case bucket = "bucket"
        case role = "role"
        case userId = "user_id"
    }
}

// MARK: - Settings
struct UserSettings: Codable {
    let notificationsEnabled: Bool?
    let language: String?
    let timezone: String?
    let fcmToken: String?

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
        case language
        case timezone
        case fcmToken = "fcm_token"
    }
}

// MARK: - Auth Info
struct UserAuth: Codable {
    let lastLoginAt: String?
    let isLocked: Bool?

    enum CodingKeys: String, CodingKey {
        case lastLoginAt = "last_login_at"
        case isLocked = "is_locked"
    }
}

// MARK: - Role
struct UserRole: Codable {
    let id: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

