//
//  DatabaseKeyManager.swift
//  PillCounter
//
//  Created by Ritesh Parekh on 15/05/26.
//

import Foundation
import Security

enum DatabaseKeyManager {

    private static let service = "com.ritetechnologies.PillCounting"
    private static let account = "db_encryption_key_v1"

    // MARK: - Public API

    /// Returns the existing database key, or generates and stores a new one
    /// on first call. This is the ONLY entry point — all of CoreDataManager
    /// should call this once during init.
    static func getOrCreatePassphrase() -> String {
        if let existing = loadKey() { return existing }
        let newKey = generateKey()
        saveKey(newKey)
        return newKey
    }

    // MARK: - Key generation

    private static func generateKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            fatalError("SecRandomCopyBytes failed with status \(status)")
        }
     
        return "x'" + bytes.map { String(format: "%02x", $0) }.joined() + "'"
    }

    // MARK: - Keychain read

    private static func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key  = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }

    // MARK: - Keychain write

    private static func saveKey(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }

        let attributes: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:        data,
        ]
        SecItemDelete(attributes as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status != errSecSuccess {
            #if DEBUG
            Log("⚠️  DatabaseKeyManager: Keychain write failed with status \(status)")
            #endif
        }
    }
}
