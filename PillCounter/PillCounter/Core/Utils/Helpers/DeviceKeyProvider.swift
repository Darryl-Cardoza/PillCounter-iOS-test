//
//  DeviceKeyProvider.swift
//  PillCounter
//

import UIKit

/// Stable per-device identifier used to determine which terminal this install
/// currently holds. Cached in the Keychain (not UserDefaults) so the same value
/// survives an app delete + reinstall on the same device — only a device wipe or
/// a fresh device generates a new one. Seeded from `identifierForVendor` on first
/// read.
final class DeviceKeyProvider {
    static let shared = DeviceKeyProvider()
    private init() {}

    static let keychainAccount = "deviceKey"

    func getDeviceKey() -> String {
        if let cached = Keychain.getPassword(for: Self.keychainAccount) {
            return cached
        }
        let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        Keychain.savePassword(id, for: Self.keychainAccount)
        return id
    }
}
