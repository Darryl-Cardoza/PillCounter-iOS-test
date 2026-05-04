//
//  KeychainHelper.swift
//  PillCounter
//
//  Created by Bhushan Patil on 04/05/26.
//

import Security
import Foundation
import CryptoKit

struct KeychainHelper {

    static let shared = KeychainHelper()
    private init() {}

    private let keyTag = "com.pillcounter.imageEncryptionKey"

    // Retrieve existing key or generate + store a new one
    func getOrCreateEncryptionKey() -> SymmetricKey {
        if let existing = loadKey() { return existing }
        let newKey = SymmetricKey(size: .bits256)
        saveKey(newKey)
        return newKey
    }

    private func saveKey(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      keyTag,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String:        keyData
        ]
        SecItemDelete(query as CFDictionary)   // remove stale entry first
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return SymmetricKey(data: data)
    }
}
