//
//  Keychain.swift
//  PillCounter
//
//  Created by HC on 05/11/25.
//

import Foundation
import Security

final class Keychain {

    static func savePassword(_ password: String, for key: String, service: String = "PillCounter") {
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func getPassword(for key: String, service: String = "PillCounter")
        -> String?
    {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let password = String(data: data, encoding: .utf8)
        {
            return password
        }
        return nil
    }
    
    static func deletePassword(for key: String, service: String = "PillCounter") {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
