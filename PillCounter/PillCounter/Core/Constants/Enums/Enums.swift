//
//  Enums.swift
//  PillCounter
//
//  Created by HC on 31/10/25.
//

import SwiftUI

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public enum PillCounterFlow: Hashable, Codable {
    case authentication(AuthenticationFlow)
}

public enum AuthenticationFlow: Hashable, Codable {
    case login(LoginFlow)
    case user(UserFlow)
}

public enum LoginFlow: Hashable, Codable {
    case LoginEmail
    case otpVerificationLogin
    case dashboard(DashboardFlow)
}

public enum DashboardFlow: Hashable, Codable {
    case dashboardHome
    case fixedCountPartial
    case pillCount(ScanningFlow)
}

public enum ScanningFlow: Codable, Hashable {
    case barcodeScanning(ScanType)
    case unifiedCamera(ScanType)
    case pillCountView
    case pillCountHistoryView
    case stockCount(StockCountFlow)
}

public enum StockCountFlow: Codable, Hashable {
    case stockCountBatchDetail
    case stockCountPartialBatchListScreen
}



public enum UserFlow: Hashable, Codable {
    case hamburgerMenu
    case userSettings(HamburgerMenuFLow)
}


public enum ScanType: Codable, Hashable {
    case barcode
    case stockCount
    case rx_label

    var instructionText: String {
        switch self {
        case .barcode:
            return L10n.Controlled.scanBarcode
        case .stockCount:
            return L10n.Controlled.scanStockCountBarcode
        case .rx_label:
            return L10n.Controlled.scanRxLabelBarcode
        }
    }
}


public enum HamburgerMenuFLow: Hashable, Codable {
    case History(HistoryFilterType, HistoryStatusFilter)
    case profile
    case settings
    case unsyncedTransaction
    case HistoryTransactionDetail
    case HistoryBatchDetail
}

public enum HamburgerMenuItem: CaseIterable, Identifiable {
    case FixedCount
    case RegularCount
    case History
    case UnsyncedTransaction
    case Settings
    case Profile
    case Logout

    public var id: String { title }

    var title: String {
        switch self {
            case .FixedCount:
                return L10n.Dashboard.FixedCount.title
            case .RegularCount:
                return L10n.Dashboard.RegularCount.title
            case .Profile: return L10n.Menu.profile
            case .History: return L10n.Menu.history
            case .UnsyncedTransaction: return L10n.Menu.unsync
            case .Settings: return L10n.Menu.settings
            case .Logout: return L10n.Menu.logout
        }
        
    }

    var iconName: String {
        switch self {
        case .FixedCount: return "target_count_step3"
        case .RegularCount: return "placeholder_history"
        case .Profile: return "profile_icon"
        case .History: return "history_icon"
        case .UnsyncedTransaction: return "unsync_icon"
        case .Settings: return "settings_icon"
        case .Logout: return "logout_icon"
        }
    }
}

enum SaveHistoryOption: String, CaseIterable, Identifiable {
    case oneWeek = "1 Week (Default)"
    case fifteenDays = "15 Days"
    case oneMonth = "1 Month"
    case twoMonths = "2 Months"
    case threeMonths = "3 Months"

    var id: String { rawValue }

    /// Display text for UI
    var displayText: String {
        return rawValue
    }

    /// Default value
    static var `default`: SaveHistoryOption {
        return .oneWeek
    }

    // [NEW] Helper to get the cutoff date
    func getCutoffDate() -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var dateComponent = DateComponents()

        switch self {
        case .oneWeek: dateComponent.day = -7
        case .fifteenDays: dateComponent.day = -15
        case .oneMonth: dateComponent.month = -1
        case .twoMonths: dateComponent.month = -2
        case .threeMonths: dateComponent.month = -3
        }

        return calendar.date(byAdding: dateComponent, to: now)
    }
}

enum TransactionDetailOption: String, CaseIterable, Identifiable {
    case resume = "RESUME"
    case forceComplete = "FORCE COMPLETE"
    case delete = "DELETE"

    var id: String { rawValue }
}

enum CountType: String, Codable {
    case REGULAR
    case FIXED
}

enum CountStatus: String, Codable {
    case PARTIAL
    case COMPLETED
    case FORCE_COMPLETED
}

public enum HistoryStatusFilter: String, CaseIterable, Codable {
    case all       = "All"
    case completed = "Completed"
    case pending   = "Pending"
}

public enum InputValidation {
    case none
    case name
    case phone
    case email
    case npi
}
    
enum PmsFilter: Hashable {
    case all
    case pms
    case nonPms
}



enum ControlledStep: String, CaseIterable {
    case scan = "SCAN"
    case containerInitiate = "CONTAINER_INITIATE"
    case targetVerification = "TARGET_VERIFICATION"
    case targetReverification = "TARGET_REVERIFICATION"
    case vial = "VIAL"
    case containerPending = "CONTAINER_PENDING"
    
    var displayText: String {
        switch self {
        case .scan:
            return L10n.Controlled.scan
        case .containerInitiate:
            return L10n.Controlled.containerInitiate
        case .targetVerification:
            return L10n.Controlled.targetVerification
        case .targetReverification:
            return L10n.Controlled.targetReverification
        case .vial:
            return L10n.Controlled.vial
        case .containerPending:
            return L10n.Controlled.containerPending
        }
    }
    

}

public enum StockCountOption: Hashable {
    case newBatch
    case existingBatch
}

public enum StockCountOptionContainerStatus: Hashable {
    case sealed
    case opened
}


//HL7 ENUMS
public enum PmsConnectionState {
    case connected
    case disconnected
    case connecting
    case notAvailable
}


/// Handles MLLP framing for HL7 messages over TCP.
enum MLLP {

    /// Start block <VT>
    static let start: UInt8 = 0x0B

    /// End block <FS>
    static let end1: UInt8 = 0x1C

    /// Carriage return <CR>
    static let end2: UInt8 = 0x0D

    /// Wraps HL7 message with MLLP framing.
    static func frame(_ message: String) -> Data {
        var data = Data([start])
        data.append(message.data(using: .utf8)!) // HL7 payload
        data.append(contentsOf: [end1, end2])    // End markers
        return data
    }

    /// Extracts HL7 message from MLLP framed data.
    static func unwrap(_ data: Data) -> String? {
        guard
            let startIndex = data.firstIndex(of: start),
            let endIndex = data.firstIndex(of: end1)
        else { return nil }

        let payload = data[(startIndex + 1)..<endIndex]
        return String(data: payload, encoding: .utf8)
    }
}


//Settings

enum DrugSchedule: String, CaseIterable, Identifiable {
    case cii = "CII"
    case ciii = "CIII"
    case civ = "CIV"
    case cv = "CV"
    case cvi = "CVI"

    var id: String { rawValue }
}

enum SettingsSubScreen {
    case saveHistory
    case schedule
}



// MARK: History
public enum HistoryFilterType: String, Codable, Hashable {
    case fixed
    case regular
}

