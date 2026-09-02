// DAOLogger.swift
// PillCounter
//
// Prints query results in a fixed-width ASCII table to the Xcode console.
// Usage: DAOLogger.log(dao: "TransactionDAO", op: "fetchAll", columns: [...], rows: [[...]])

import Foundation

enum StoreLogger {

    // MARK: - Public entry points

    /// Log a query that returned a list of rows. No-op outside DEBUG builds —
    /// building/printing this table (which scans every row) is pure
    /// production overhead with no consumer.
    static func log(dao: String, op: String, columns: [String], rows: [[String]]) {
        #if DEBUG
        guard !rows.isEmpty else {
            print("[\(dao)] \(op) → (0 rows)")
            return
        }
        let widths = columnWidths(columns: columns, rows: rows)
        let header  = buildRow(cells: columns, widths: widths)
        let divider = buildDivider(widths: widths)
        let body    = rows.map { buildRow(cells: $0, widths: widths) }.joined(separator: "\n")
        print("""
            [\(dao)] \(op) → \(rows.count) row(s)
            \(divider)
            \(header)
            \(divider)
            \(body)
            \(divider)
            """)
        #endif
    }

    /// Log a single-row result (e.g. fetchById).
    static func logSingle(dao: String, op: String, columns: [String], row: [String]?) {
        guard let row else {
            #if DEBUG
            print("[\(dao)] \(op) → (not found)")
            #endif
            return
        }
        log(dao: dao, op: op, columns: columns, rows: [row])
    }

    /// Log a scalar result (e.g. count, total).
    static func logScalar(dao: String, op: String, label: String, value: Any) {
        log(dao: dao, op: op, columns: [label], rows: [["\(value)"]])
    }

    /// Log a free-form trace message (create/update/delete notices, errors). No-op outside DEBUG builds.
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    // MARK: - Private helpers

    private static func columnWidths(columns: [String], rows: [[String]]) -> [Int] {
        var widths = columns.map { $0.count }
        for row in rows {
            for (i, cell) in row.prefix(widths.count).enumerated() {
                widths[i] = max(widths[i], cell.count)
            }
        }
        return widths
    }

    private static func buildRow(cells: [String], widths: [Int]) -> String {
        let inner = zip(cells, widths)
            .map { cell, width in " \(cell.padding(toLength: width, withPad: " ", startingAt: 0)) " }
            .joined(separator: "|")
        return "|\(inner)|"
    }

    private static func buildDivider(widths: [Int]) -> String {
        let inner = widths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "+")
        return "+\(inner)+"
    }
}
