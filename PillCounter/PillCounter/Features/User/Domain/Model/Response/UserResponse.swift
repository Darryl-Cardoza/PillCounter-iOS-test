//
//  UserResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//
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
    
    /// Some APIs wrap data inside `user`,
    /// others expose profile/settings directly.
    
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
    let terminals: [UserTerminal]?
    
    let auth: UserAuth?
    let role: UserRole?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isVerified = "is_verified"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        
        case profile
        case settings
        case terminals
        
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
    let pharmacyType: String?
    let npiID: String?

    let isVerified: Bool?
    let isPmsIntegrated: Bool?

    let bucket: [String]?

    let role: UserRole?
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case fname
        case lname
        case email

        case phoneNumber = "phone_number"
        case avatarURL = "avatar_url"

        case isProfileCompleted = "is_profile_completed"
        case pharmacyName = "pharmacy_name"
        case pharmacyType = "pharmacy_type"
        case npiID = "npi_id"

        case isVerified = "is_verified"
        case isPmsIntegrated = "is_hl7_enabled"

        case bucket
        case role

        case userId = "user_id"
    }
}

// MARK: - Settings
struct UserSettings: Codable {
    let notificationsEnabled: Bool?
    let language: String?
    let timezone: String?
    let country: String?
    let state: String?
    let hl7Version: String?
    let fcmToken: String?
    let terminals: [UserTerminal]?
    let bucket: [String]?
    let isPmsIntegrated: Bool?
    let allowLocalStorage: Bool?
    let bypassSSL: Bool?
    let hl7MessageSpec: String?
    let isStandalone: Bool?
    let useStaticPMSConnection: Bool?
    let pmsIpAddress: String?
    let pmsPort: Int?


    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
        case language
        case timezone
        case country

        case state
        case hl7Version = "hl7_version"
        case fcmToken = "fcm_token"
        case terminals
        case bucket
        case isPmsIntegrated = "is_pms_integrated"
        case allowLocalStorage = "allow_local_storage"
        case bypassSSL = "bypass_ssl"
        case hl7MessageSpec = "hl7_message_spec"
        case isStandalone = "is_standalone"
        case useStaticPMSConnection = "use_static_pms_connection"
        case pmsIpAddress = "pms_ip"
        case pmsPort = "pms_port"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        hl7Version = try container.decodeIfPresent(String.self, forKey: .hl7Version)
        fcmToken = try container.decodeIfPresent(String.self, forKey: .fcmToken)
        terminals = try container.decodeIfPresent([UserTerminal].self, forKey: .terminals)
        bucket = try container.decodeIfPresent([String].self, forKey: .bucket)
        isPmsIntegrated = try container.decodeIfPresent(Bool.self, forKey: .isPmsIntegrated)
        allowLocalStorage = try container.decodeIfPresent(Bool.self, forKey: .allowLocalStorage)
        bypassSSL = try container.decodeIfPresent(Bool.self, forKey: .bypassSSL)
        hl7MessageSpec = try container.decodeIfPresent(String.self, forKey: .hl7MessageSpec)
        isStandalone = try container.decodeIfPresent(Bool.self, forKey: .isStandalone)
        useStaticPMSConnection = try container.decodeIfPresent(Bool.self, forKey: .useStaticPMSConnection)
        pmsIpAddress = try container.decodeIfPresent(String.self, forKey: .pmsIpAddress)
        if let intPort = (try? container.decodeIfPresent(Int.self, forKey: .pmsPort)) ?? nil {
            pmsPort = intPort
        } else if let stringPort = (try? container.decodeIfPresent(String.self, forKey: .pmsPort)) ?? nil {
            pmsPort = Int(stringPort)
        } else {
            pmsPort = nil
        }
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

// MARK: - Terminal
struct UserTerminal: Codable {
    let terminalId: String?
    let terminalName: String?
    let isActive: Bool?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case terminalId = "terminal_id"
        case terminalName = "terminal_name"
        case isActive = "is_active"
        
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
