//
//  UpdateUserProfileRequest.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct UpdateUserProfileRequest: Codable {
//    let fullName: String?
    let fname: String?
    let lname: String?
    let pharmacyName: String?
    let phoneNumber: String?
    let npiID: String?
    let isProfileComplete: Bool?
    let avatarURL: String?
    let notificationsEnabled: Bool?
    let language: String?
    let timezone: String?
    let pharmacyType: String?

    enum CodingKeys: String, CodingKey {
        case fname = "fname"
        case lname = "lname"
        case pharmacyName = "pharmacy_name"
        case phoneNumber = "phone_number"
        case npiID = "npi_id"
        case isProfileComplete = "is_profile_complete"
        case avatarURL = "avatar_url"
        case notificationsEnabled = "notifications_enabled"
        case language
        case timezone
        case pharmacyType = "pharmacy_type"
    }
}
