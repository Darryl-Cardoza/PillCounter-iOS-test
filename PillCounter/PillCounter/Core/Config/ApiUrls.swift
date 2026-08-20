//
//  ApiUrls.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct APIConstants {
    
    private static let baseURL = ConfigurationManager.shared.apiBaseURL
    
    // MARK: - AUTHENTICATION
    static let sendOTP = "\(baseURL)/auth/send/otp"
    static let verifyOTP = "\(baseURL)/auth/verify/otp"
    
    /// resend otp
    static let resendOTP = "\(baseURL)/auth/resend/otp"
    
    /// Refersh access token
    static let refreshToken = "\(baseURL)/auth/refresh"
    /// Logout
    static let logout = "\(baseURL)/auth/logout"
    
    
    // MARK: - USER
    static let getMe = "\(baseURL)/auth/me"
    
    /// Services
    static let updateProfile = "\(baseURL)/users/update/profile"
    static let updateProfilePatch = "\(baseURL)/users/profile"
    static let deleteProfile = "\(baseURL)/users/delete/profile"
    static let pharmacyTypes = "\(baseURL)/users/pharmacy-types"

    // MARK: - REFERENCE
    static let countries = "\(baseURL)/reference/countries"

    // MARK: - MOBILE
    static let getMobileSettings = "\(baseURL)/mobile/get/settings?platform" // need to add query parameter to send the ios version.
    
    // MARK: - TERMINAL
    static func updateTerminal(terminalId: String) -> String {
        "\(baseURL)/terminals/update/\(terminalId)"
    }

    static func getTerminals(availableOnly: Bool, deviceKey: String) -> String {
        var components = URLComponents(string: "\(baseURL)/terminals/list")
        components?.queryItems = [
            URLQueryItem(name: "available_only", value: String(availableOnly)),
            URLQueryItem(name: "device_key", value: deviceKey)
        ]
        return components?.url?.absoluteString ?? "\(baseURL)/terminals/list"
    }
    
    // MARK: - DRUG
    static let getControlledDrugInfo = "\(baseURL)/drugs/ndc"
    
}
