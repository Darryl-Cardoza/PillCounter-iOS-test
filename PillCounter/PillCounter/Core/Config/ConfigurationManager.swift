//
//  ConfigurationManager.swift
//  PillCounter
//
//  Created by HC on 04/11/25.
//

import Foundation

final class ConfigurationManager {

    static let shared = ConfigurationManager()
    private var config: [String: Any] = [:]

    private init() {
        loadFromBundle()
    }

    // MARK: - BUNDLE LOAD

    /// LOAD
    /// Reads non-sensitive configuration values from the app bundle.
    private func loadFromBundle() {
        guard
            let url = Bundle.main.url(
                forResource: "Config", withExtension: "plist"),
            let data = try? Data(contentsOf: url)
        else {
            return
        }

        do {
            if let dict = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
            {
                config = dict
            }
        } catch {
            #if DEBUG
            print("Config load failed:", error.localizedDescription)
            #endif
        }
    }

    // MARK: - PUBLIC ACCESS

    /// BASE URL
    /// Returns the API base URL from bundle configuration.
    var apiBaseURL: String {
        config["BASE_URL"] as? String ?? ""
    }

    /// GENERIC ACCESS
    /// Provides access to non-sensitive configuration values.
    func getValue(forKey key: String) -> Any? {
        config[key]
    }
}

