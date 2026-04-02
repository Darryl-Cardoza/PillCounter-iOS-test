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
    case regularCountPartial
    case pillCount(ScanningFlow)
}

public enum ScanningFlow: Codable, Hashable {
    case barcodeScanning
    case pillCountView
    case controlledDrug(ControlFlow)
    case stockCount(StockCountFlow)
}

public enum StockCountFlow: Codable, Hashable {
    case stockCountBatchDetail
    case stockCountPartialBatchListScreen
    case stockCountPendingBatchListScreen
}

public enum ControlFlow: Hashable, Codable {
    case vialCount
}

public enum UserFlow: Hashable, Codable {
    case hamburgerMenu
    case userSettings(HamburgerMenuFLow)
}



public enum HamburgerMenuFLow: Hashable, Codable {
    case History(HistoryFilterType)
    case profile
    case settings
    case unsyncedTransaction
    case HistoryTransactionDetail
}

public enum HamburgerMenuItem: CaseIterable, Identifiable {
    case FixedCount
    case RegularCount
    case Profile
    case History
    case UnsyncedTransaction
    case Settings
    case Logout

    public var id: String { title }

    var title: String {
        switch self {
            case .FixedCount:
                return NSLocalizedString("FIXED_COUNT_TITLE", comment: "")
            case .RegularCount:
                return NSLocalizedString("REGULAR_COUNT_TITLE", comment: "")
            case .Profile: return NSLocalizedString("PROFILE", comment: "")
            case .History: return NSLocalizedString("HISTORY", comment: "")
            case .UnsyncedTransaction:return NSLocalizedString("Unsynced Transactions", comment: "")
            case .Settings: return NSLocalizedString("SETTINGS", comment: "")
            case .Logout: return NSLocalizedString("LOGOUT", comment: "")
        }
        
    }

    var iconName: String {

        switch self {
        case .FixedCount: return "fixed_count_icon"
        case .RegularCount: return "regular_count_icon"
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

public enum InputValidation {
    case none
    case name
    case phone
    case email
    case npi
}
    

public enum HistoryFilterType: String, Codable, Hashable {
    case all
    case fixed
    case regular
    
    var title: String {
          switch self {
          case .all:
              return NSLocalizedString("HISTORY", comment: "")
          case .fixed:
              return "Fixed Count History"
          case .regular:
              return "Quick Count History"
          }
      }
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
            return "Scan Container QR Code"
        case .containerInitiate:
            return "Count all pills from container"
        case .targetVerification:
            return "Count Prescribed quantity"
        case .targetReverification:
            return "Recount Prescribed Quantity."
        case .vial:
            return "Take picture of the counted Pills Vial"
        case .containerPending:
            return "Count all remaining Pills from Container"
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
