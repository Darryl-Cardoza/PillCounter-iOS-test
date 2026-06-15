//
//  MobileSettingsResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct MobileSettingsResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: MobileSettingsData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct MobileSettingsData: Codable {
    let isMaintenanceMode: Bool?
    let settings: AppSettings?
    let iosVersion: String?
    let hl7Config:AppHl7Config?

    enum CodingKeys: String, CodingKey {
        case isMaintenanceMode = "is_maintenance_mode"
        case settings
        case iosVersion = "ios_version"
        case hl7Config = "hl7_config"
    }
}

struct AppSettings: Codable {
    let colors: AppColorScheme?
    let appLogo: String?
    let placeholderLogo: String?

    enum CodingKeys: String, CodingKey {
        case colors
        case appLogo
        case placeholderLogo
    }
}

struct AppColorScheme: Codable {
    let light: AppColorPalette?
    let dark: AppColorPalette?
}

struct AppColorPalette: Codable {
    let primary: String?
    let secondary: String?
    let tertiary: String?
    let primaryBackground: String?
    let secondaryBackground: String?
    let textColor: String?
    let inputBackground: String?
    let statusChipBackgroundOnPrimary: String?
    let statusChipBackgroundOnSecondary: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case tertiary
        case primaryBackground
        case secondaryBackground
        case textColor
        case inputBackground
        case statusChipBackgroundOnPrimary
        case statusChipBackgroundOnSecondary
    }
}

struct AppHl7Config: Codable {
    let pmsHostName: String?
    let pillCounterHostName: String?
    let barcodeFormat: String?
    
    enum CodingKeys: String, CodingKey {
        case pmsHostName = "pms_host_name"
        case pillCounterHostName = "pillcounter_host_name"
        case barcodeFormat = "barcode_format"
    }
}
