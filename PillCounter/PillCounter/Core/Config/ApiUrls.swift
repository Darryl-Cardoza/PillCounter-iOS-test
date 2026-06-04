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
    static let deleteProfile = "\(baseURL)/users/delete/profile"
    
    
    // MARK: - MOBILE
    static let getMobileSettings = "\(baseURL)/mobile/get/settings?platform" // need to add query parameter to send the ios version.
    
    // MARK: - TERMINAL
    static func updateTerminal(terminalId: String) -> String {
        "\(baseURL)/terminals/update/\(terminalId)"
    }
    
    // MARK: - DRUG
    static let getControlledDrugInfo = "\(baseURL)/drugs/ndc"
    
}
