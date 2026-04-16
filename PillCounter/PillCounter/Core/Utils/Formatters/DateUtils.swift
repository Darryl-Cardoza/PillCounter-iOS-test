//
//  DateUtils.swift
//  PillCounter
//
//  Created by Bhushan Patil on 14/04/26.
//

//
import Foundation

struct DateUtils {

    static func formatToDayMonthYearTime(_ timestamp: Int64?) -> String {
        guard let timestamp else { return "" }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)

        let formatter = Foundation.DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy hh:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return formatter.string(from: date)
    }
    
    
    // MARK: - Timestamp
    static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }

}
