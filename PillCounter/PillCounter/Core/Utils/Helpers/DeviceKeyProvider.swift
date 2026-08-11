//
//  DeviceKeyProvider.swift
//  PillCounter
//

import UIKit

/// Stable per-device identifier used to determine which terminal this install
/// currently holds. Sourced from `identifierForVendor` — Apple's recommended
/// per-device unique ID — cached after first read so it's stable across launches.
final class DeviceKeyProvider {
    static let shared = DeviceKeyProvider()
    private init() {}

    func getDeviceKey() -> String {
        if let cached = AppStorageManager.shared.deviceKey { return cached }
        let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        AppStorageManager.shared.deviceKey = id
        return id
    }
}
