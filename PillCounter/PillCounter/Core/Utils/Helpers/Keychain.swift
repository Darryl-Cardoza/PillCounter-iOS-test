//
//  Keychain.swift
//  PillCounter
//
//  Single Keychain wrapper for the app. Replaces the former trio:
//  Keychain (string values), KeychainHelper (image-encryption key) and the
//  private key methods inside FieldEncryptionManager.
//
//  Layering:
//   • Data layer — generic get/set/delete keyed by (account, service), with
//     configurable accessibility. Every typed accessor maps onto it.
//   • String layer — the original `savePassword`/`getPassword`/... API, kept
//     byte-for-byte compatible (same default service + accessibility) so all
//     existing call sites and stored items continue to work.
//   • SymmetricKey layer — for AES keys (image + field encryption).
//
//  ⚠️ The exact (account, service, accessibility) tuples below are deliberately
//  preserved from the original wrappers. Changing any of them makes previously
//  stored items unreadable (a different query no longer matches), which would
//  silently regenerate keys and make existing encrypted data undecryptable.
//

import Foundation
import Security
import CryptoKit

final class Keychain {

    /// Default service used by the string password API.
    static let defaultService = "com.ritetechnologies.PillCounting"

    // MARK: - Data layer (generic)

    /// Saves (overwriting any existing item) raw data for `account`.
    /// `service` may be nil to match items stored without a service attribute.
    @discardableResult
    static func setData(
        _ data: Data,
        account: String,
        service: String? = defaultService,
        accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ) -> Bool {
        deleteData(account: account, service: service)

        var query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrAccount as String:    account,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String:      data,
        ]
        if let service { query[kSecAttrService as String] = service }

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Reads raw data for `account`, or nil if absent.
    static func data(
        account: String,
        service: String? = defaultService
    ) -> Data? {
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        if let service { query[kSecAttrService as String] = service }

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return data
    }

    /// Deletes the item for `account`.
    static func deleteData(
        account: String,
        service: String? = defaultService
    ) {
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        if let service { query[kSecAttrService as String] = service }
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - String layer (original public API)

    /// Saves (or overwrites) a string value in the Keychain.
    static func savePassword(
        _ password: String,
        for key: String,
        service: String = defaultService
    ) {
        guard let data = password.data(using: .utf8) else { return }
        setData(data, account: key, service: service)
    }

    static func getPassword(
        for key: String,
        service: String = defaultService
    ) -> String? {
        guard let data = data(account: key, service: service) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(
        for key: String,
        service: String = defaultService
    ) {
        deleteData(account: key, service: service)
    }

    /// Removes every generic-password item under `service`.
    static func deleteAll(service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Removes every generic-password item under `service` EXCEPT the given
    /// accounts. Used where a blanket wipe (logout, fresh-install cleanup)
    /// must not destroy state that's meant to outlive it — e.g. the wrapped
    /// DEK bookkeeping that must survive logout so a returning user's already
    /// -encrypted CoreData fields/photos stay decryptable.
    ///
    /// `SecItemDelete` has no "not equal" matcher, so this enumerates
    /// matching accounts first and deletes everything not in `preservedAccounts`.
    static func deleteAll(service: String = defaultService, preservedAccounts: Set<String>) {
        guard !preservedAccounts.isEmpty else {
            deleteAll(service: service)
            return
        }

        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String:   kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return }

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  !preservedAccounts.contains(account)
            else { continue }
            deleteData(account: account, service: service)
        }
    }

    // MARK: - SymmetricKey layer (AES keys)

    /// Returns the AES key stored for `account`/`service`, or generates a new
    /// 256-bit key, stores it, and returns that.
    ///
    /// Known limitation (tracked, not fixed): the check-then-create sequence
    /// below has no lock. Two concurrent first-time calls for the same
    /// `account` can each observe "no key yet," generate different keys, and
    /// race on `setData` — whichever write loses leaves its caller holding a
    /// key that was never persisted, silently orphaning anything sealed
    /// under it. Low probability in practice (callers generally hit this
    /// once per alias, well before concurrent access is likely), but a real
    /// gap if two callers ever race a brand-new alias's first use.
    static func getOrCreateSymmetricKey(
        account: String,
        service: String? = defaultService,
        accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ) -> SymmetricKey {
        if let existing = data(account: account, service: service) {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        setData(keyData, account: account, service: service, accessibility: accessibility)
        return key
    }
}
