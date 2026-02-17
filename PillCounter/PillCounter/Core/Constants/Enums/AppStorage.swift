//
//  AppStorage.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

final class AppStorageManager {
    static let shared = AppStorageManager()  // Singleton instance
    private let defaults = UserDefaults.standard
    private init() {}

    // MARK: - AppStorageKeys
    public enum AppStorageKeys {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let userId = "user_id"
        static let rememberMe = "remember_me"
        static let userSavedEmails = "user_saved_emails"
        static let isLoggedIn = "is_logged_in"
        static let userEmail = "user_email"
        static let drugIdCounter = "drug_id_counter"
        static let isNewUser = "is_new_user"
        static let tokenExpiryTimestamp = "token_expiry_timestamp"
        static let saveHistoryOption = "save_history_option"
        static let isPillCountingEnabled = "is_pill_counting_enabled"
        static let isHl7Enable: String = "is_hl7_enable"
        static let pmsHostName = "pms_host_name"
        static let pillCounterHostName = "pillcounter_host_name"
    }

    // MARK: - Access Token
    var accessToken: String? {
        get { defaults.string(forKey: AppStorageKeys.accessToken) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.accessToken) }
    }

    // MARK: DRUG ID COUNTER.
    var drugIdCounter: Int? {
        get { defaults.integer(forKey: AppStorageKeys.drugIdCounter) }
        set {
            defaults.setValue(newValue, forKey: AppStorageKeys.drugIdCounter)
        }
    }

    // MARK: - Refresh Token
    var refreshToken: String? {
        get { defaults.string(forKey: AppStorageKeys.refreshToken) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.refreshToken) }
    }

    var userEmail: String? {
        get { defaults.string(forKey: AppStorageKeys.userEmail) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.userEmail) }
    }

    // MARK: IS LOGGED IN
    var isLoggedIn: Bool? {
        get { defaults.bool(forKey: AppStorageKeys.isLoggedIn) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isLoggedIn) }
    }
    
    // MARK: IS NEW USER
    var isNewUser: Bool? {
        get { defaults.bool(forKey: AppStorageKeys.isNewUser) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isNewUser) }
    }

    // MARK: - User ID
    var userId: String? {
        get { defaults.string(forKey: AppStorageKeys.userId) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.userId) }
    }

    // MARK: - User Saved Emails
    var userSavedEmails: [String] {
        get {
            if let data = defaults.data(forKey: AppStorageKeys.userSavedEmails),
                let emails = try? JSONDecoder().decode(
                    [String].self, from: data)
            {
                return emails
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.setValue(data, forKey: AppStorageKeys.userSavedEmails)
            }
        }
    }
    
    // MARK: - Pill Counting Toggle
    var isPillCountingEnabled: Bool {
        get {
            // defaults.bool returns false if key is missing
            defaults.bool(forKey: AppStorageKeys.isPillCountingEnabled)
        }
        set {
            defaults.setValue(newValue, forKey: AppStorageKeys.isPillCountingEnabled)
        }
    }
    
    //MARK: - Pill Counting HL7 enabled
    var isHl7Enabled: Bool {
        get {
            defaults.bool(forKey: AppStorageKeys.isHl7Enable)
        }
        set {
            defaults.setValue(newValue, forKey: AppStorageKeys.isHl7Enable)
        }
    }
    
    var pmsHostName: String {
        get {
            defaults.string(forKey: AppStorageKeys.pmsHostName) ?? ""
        }
        set {
            defaults.setValue(newValue, forKey: AppStorageKeys.pmsHostName)
        }
    }

    var pillCounterHostName: String {
        get {
            defaults.string(forKey: AppStorageKeys.pillCounterHostName) ?? ""
        }
        set {
            defaults.setValue(newValue, forKey: AppStorageKeys.pillCounterHostName)
        }
    }
    
 

    // MARK: - Add email
    func addEmail(_ email: String) {
        guard !userSavedEmails.contains(email) else { return }
        userSavedEmails.append(email)
    }

    // MARK: - Clear emails
    func clearEmails() {
        userSavedEmails.removeAll()
    }

    // MARK: - Remember Me
    var rememberMe: Bool? {
        get { defaults.bool(forKey: AppStorageKeys.rememberMe) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.rememberMe) }
    }

    // MARK: - Save History Option (New Implementation)
    var saveHistoryOption: SaveHistoryOption {
        get {
            // 1. Try to get the string from UserDefaults
            guard
                let rawValue = defaults.string(
                    forKey: AppStorageKeys.saveHistoryOption),
                // 2. Try to convert string back to Enum
                let option = SaveHistoryOption(rawValue: rawValue)
            else {
                // 3. If missing or invalid, return default
                return .default
            }
            return option
        }
        set {
            // 4. Save the String representation (rawValue) of the enum
            defaults.setValue(
                newValue.rawValue, forKey: AppStorageKeys.saveHistoryOption)
        }
    }
    
    // MARK: - Token Expiry
    // We store this as a Double (TimeIntervalSince1970)
    var tokenExpiryTimestamp: Double? {
        get { defaults.double(forKey: AppStorageKeys.tokenExpiryTimestamp) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.tokenExpiryTimestamp) }
    }

    // MARK: - Utility
    func clearUserSession() {
        defaults.removeObject(forKey: AppStorageKeys.accessToken)
        defaults.removeObject(forKey: AppStorageKeys.refreshToken)
        defaults.removeObject(forKey: AppStorageKeys.userId)
        defaults.removeObject(forKey: AppStorageKeys.rememberMe)
        defaults.removeObject(forKey: AppStorageKeys.userSavedEmails)
    }

    // MARK: Logout
    func logout() {
        print("🔴 BEFORE LOGOUT userId =", defaults.string(forKey: AppStorageKeys.userId) ?? "nil")
        defaults.removeObject(forKey: AppStorageKeys.accessToken)
        defaults.removeObject(forKey: AppStorageKeys.refreshToken)
        defaults.removeObject(forKey: AppStorageKeys.rememberMe)
        defaults.removeObject(forKey: AppStorageKeys.userEmail)
        defaults.removeObject(forKey: AppStorageKeys.userId)
        defaults.removeObject(forKey: AppStorageKeys.isLoggedIn)
        defaults.removeObject(forKey: AppStorageKeys.tokenExpiryTimestamp)
        defaults.removeObject(forKey: AppStorageKeys.isHl7Enable)
        defaults.removeObject(forKey: AppStorageKeys.pmsHostName)
        defaults.removeObject(forKey: AppStorageKeys.pillCounterHostName)
        print("🟢 AFTER LOGOUT userId =", defaults.string(forKey: AppStorageKeys.userId) ?? "nil")
    }
}
