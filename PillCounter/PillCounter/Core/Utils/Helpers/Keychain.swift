//
//  Keychain.swift
//  PillCounter
//

import Foundation
import Security

final class Keychain {

    private static let defaultService = "com.ritetechnologies.PillCounting"

    // MARK: - Save
    /// Saves (or overwrites) a string value in the Keychain.
    static func savePassword(
        _ password: String,
        for key: String,
        service: String = defaultService
    ) {
        guard let data = password.data(using: .utf8) else { return }

        deletePassword(for: key, service: service)

        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrAccount as String:     key,
            kSecAttrService as String:     service,
            kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String:       data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Get
    static func getPassword(
        for key: String,
        service: String = defaultService
    ) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    // MARK: - Delete
    static func deletePassword(
        for key: String,
        service: String = defaultService
    ) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Delete All
    static func deleteAll(service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
