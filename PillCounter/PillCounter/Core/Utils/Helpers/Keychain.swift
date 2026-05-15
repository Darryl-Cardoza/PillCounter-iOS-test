//
//  Keychain.swift
//  PillCounter
//
//  Created by HC on 05/11/25.
//

import Foundation
import Security
 
final class Keychain {
 
    // MARK: - Save
    static func savePassword(
        _ password: String, for key: String, service: String = "PillCounter"
    ) {
        guard let data = password.data(using: .utf8) else { return }
 
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key,
            kSecAttrService as String:      service,
            // ThisDeviceOnly — token cannot be restored from iCloud backup
            // or migrated to another device via encrypted backup.
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
 
        // Delete any stale entry first so SecItemAdd never returns
        // errSecDuplicateItem and silently discards the new value.
        SecItemDelete(query as CFDictionary)
 
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }
 
    // MARK: - Read
    static func getPassword(for key: String, service: String = "PillCounter") -> String? {
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
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return password
    }
 
    // MARK: - Delete
    static func deletePassword(for key: String, service: String = "PillCounter") {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
