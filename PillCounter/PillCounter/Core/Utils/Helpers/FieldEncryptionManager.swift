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
            let key = loadOrCreateKey()
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
    ///
    /// Important: if the value IS structured AES-GCM ciphertext but cannot be
    /// opened (wrong/rotated/unavailable key, corruption), this returns nil —
    /// never the raw ciphertext. Returning ciphertext here is what previously
    /// leaked encrypted blobs into the UI. Callers should treat nil as "no
    /// readable value" rather than rendering it.
    func decrypt(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return value }
        guard let data = Data(base64Encoded: value) else {
            // Not base64 — was not encrypted, return as-is (migration safety)
            return value
        }

        // Determine whether this is genuinely GCM-structured ciphertext.
        // If SealedBox can't even parse it, it's not our ciphertext —
        // treat as legacy plaintext that happens to be base64 and return as-is.
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(combined: data)
        } catch {
            return value
        }

        do {
            let key = loadOrCreateKey()
            let decrypted = try AES.GCM.open(sealed, using: key)
            return String(data: decrypted, encoding: .utf8)
        } catch {
            // It is real ciphertext but we cannot decrypt it (key mismatch /
            // unavailable / corruption). Do NOT return the ciphertext — that
            // would render an encrypted blob in the UI. Surface nil instead.
            Log("❌ FieldEncryption: decrypt failed on ciphertext — \(error.localizedDescription)")
            return nil
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

    // Account/service/accessibility preserved exactly from the original
    // implementation so the existing field-encryption key stays readable.
    // WhenUnlockedThisDeviceOnly: device-bound, not backed up to iCloud.
    private static let keyAccount = "com.pillcounter.field.encryption.key.v1"
    private static let keyService = "com.ritetechnologies.PillCounting"

    /// Loads the AES-256-GCM field key from the Keychain, or generates and
    /// stores a new one.
    private func loadOrCreateKey() -> SymmetricKey {
        Keychain.getOrCreateSymmetricKey(
            account: Self.keyAccount,
            service: Self.keyService,
            accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
    }
}
