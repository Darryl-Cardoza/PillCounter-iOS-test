//
//  DatabaseKeyManager.swift
//  PillCounter
//
//  Generates and stores the SQLCipher database encryption key in the Keychain.
//
//  Key format: plain base64 string passed directly to sqlite3_key().
//  sqlite3_key() accepts the passphrase as raw bytes — no SQL quoting needed.
//  Base64 gives 256 bits of entropy and is safe to store as a UTF-8 string.
//

import Foundation
import Security
import CryptoKit

enum DatabaseKeyManager {

    private static let service = "com.ritetechnologies.PillCounting"
    private static let account = "db_encryption_key_v2"

    // MARK: - Public API

    static func getOrCreatePassphrase() -> String {
        if let existing = loadKey() { return existing }
        let newKey = generateKey()
        saveKey(newKey)
        return newKey
    }

    // MARK: - Key generation
    // 32 random bytes (256 bits) encoded as base64.
    // Passed directly to sqlite3_key() as a UTF-8 string.
    private static func generateKey() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
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

        #if DEBUG
        if status != errSecSuccess {
            Log("⚠️ DatabaseKeyManager: Keychain write failed with status \(status)")
        }
        #endif
    }
}
