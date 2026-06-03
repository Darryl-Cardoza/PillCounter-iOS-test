//
//  FieldEncryptionManager.swift
//  PillCounter
//
//

import CryptoKit
import Foundation
import Security

final class FieldEncryptionManager {

    static let shared = FieldEncryptionManager()
    private init() {}

    // MARK: - Public API

    /// Encrypts a string. Returns the original string if encryption fails
    /// so the app continues to function — log the failure for investigation.
    func encrypt(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return value }
        guard let data = value.data(using: .utf8) else { return value }

        do {
            let key = try loadOrCreateKey()
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return value }
            return combined.base64EncodedString()
        } catch {
            Log("❌ FieldEncryption: encrypt failed — \(error.localizedDescription)")
            return value
        }
    }

    /// Decrypts a string encrypted by encrypt(). Returns the original
    /// string unchanged if it was not encrypted (safe for migration).
    func decrypt(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return value }
        guard let data = Data(base64Encoded: value) else {
            // Not base64 — was not encrypted, return as-is (migration safety)
            return value
        }

        do {
            let key = try loadOrCreateKey()
            let sealed = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(sealed, using: key)
            return String(data: decrypted, encoding: .utf8) ?? value
        } catch {
            // Decryption failed — may be plaintext data from before encryption
            // was introduced. Return as-is so existing data is not lost.
            return value
        }
    }

    /// Encrypts an Int64 value.
    func encrypt(_ value: Int64) -> String? {
        return encrypt(String(value))
    }

    /// Decrypts back to Int64.
    func decryptInt64(_ value: String?) -> Int64? {
        guard let str = decrypt(value) else { return nil }
        return Int64(str)
    }

    /// Encrypts a Bool value.
    func encrypt(_ value: Bool) -> String? {
        return encrypt(value ? "1" : "0")
    }

    /// Decrypts back to Bool.
    func decryptBool(_ value: String?) -> Bool {
        return decrypt(value) == "1"
    }

    // MARK: - Key management

    private static let keyAccount = "com.pillcounter.field.encryption.key.v1"
    private static let keyService = "com.ritetechnologies.PillCounting"

    /// Loads the AES-256-GCM key from Keychain, or generates and stores
    /// a new one. Key is stored with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    /// — device-bound, not backed up to iCloud.
    private func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = loadKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        try saveKey(key)
        return key
    }

    private func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keyService,
            kSecAttrAccount as String: Self.keyAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return SymmetricKey(data: data)
    }

    private func saveKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     Self.keyService,
            kSecAttrAccount as String:     Self.keyAccount,
            kSecAttrAccessible as String:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:       keyData
        ]
        SecItemDelete(attributes as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(
                domain: "FieldEncryption",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain write failed: \(status)"]
            )
        }
    }
}
