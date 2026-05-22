//
//  DBDebugLogger.swift
//  PillCounter
//

import CoreData

#if DEBUG
final class DBDebugLogger {

    static func printAll() {
        printUsers()
        printDrugMaster()
        printBatches()
        printTransactions()
        printTransactionDetails()
    }

    // MARK: - Users

    static func printUsers() {
        let rows = UserStore.shared.fetchAll()
        let header = "| user_id | fname | lname | email | phone | pharmacy | npi | verified | lang | timezone | notifications | created_at |"
        let sep    = String(repeating: "-", count: header.count)
        print("\n👤 USERS (\(rows.count) rows)")
        print(sep)
        print(header)
        print(sep)
        for r in rows {
            let createdAt = r.created_at.map { formatDate($0) } ?? "-"
            print("| \(r.user_id) | \(r.fname ?? "") | \(r.lname ?? "") | \(r.email ?? "") | \(r.phone_number ?? "") | \(r.pharmacy_name ?? "") | \(r.npi_id ?? "") | \(r.is_verified) | \(r.language ?? "") | \(r.timezone ?? "") | \(r.notifications) | \(createdAt) |")
        }
        print(sep)
    }

    // MARK: - DrugMaster

    static func printDrugMaster() {
        let rows = DrugCatalogStore.shared.fetchAll()
        let header = "| drug_id | ndc | gtin | drug_name | drug_type | package_qty | created_at |"
        let sep    = String(repeating: "-", count: header.count)
        print("\n💊 DRUG MASTER (\(rows.count) rows)")
        print(sep)
        print(header)
        print(sep)
        for r in rows {
            let ts = r.created_at > 0 ? formatTs(r.created_at) : "-"
            print("| \(r.drug_id) | \(r.ndc ?? "") | \(r.gtin ?? "") | \(r.drug_name ?? "") | \(r.drug_type ?? "") | \(r.package_qty) | \(ts) |")
        }
        print(sep)
    }

    // MARK: - Batches

    static func printBatches() {
        let rows = BatchStore.shared.fetchAll()
        let header = "| batch_id | bucket_id | req_id_from_pms | status | is_deleted | is_synced | note | start_date_time | end_date_time |"
        let sep    = String(repeating: "-", count: header.count)
        print("\n📦 BATCHES (\(rows.count) rows)")
        print(sep)
        print(header)
        print(sep)
        for r in rows {
            let start = r.start_date_time > 0 ? formatTs(r.start_date_time) : "-"
            let end   = r.end_date_time   > 0 ? formatTs(r.end_date_time)   : "-"
            print("| \(r.batch_id) | \(r.bucket_id ?? "") | \(r.req_id_from_pms ?? "") | \(r.status ?? "") | \(r.is_deleted) | \(r.is_synced) | \(r.note ?? "") | \(start) | \(end) |")
        }
        print(sep)
    }

    // MARK: - Transactions

    static func printTransactions() {
        let context = CoreDataManager.shared.context
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        let rows = (try? context.fetch(request)) ?? []

        let header = "| txn_id | drug_id | drug_name | batch_id | count_type | status | target | bottle_qty | loose_qty | is_from_pms | is_ndc_verified | is_deleted | is_synced | rx_no | lot_no | expiry | bucket_id | note | created_at | updated_at |"
        let sep    = String(repeating: "-", count: header.count)
        print("\n📋 TRANSACTIONS (\(rows.count) rows)")
        print(sep)
        print(header)
        print(sep)
        for r in rows {
            print("| \(r.txn_id) | \(r.drug_id) | \(r.drug?.drug_name ?? "") | \(r.batch_id) | \(r.count_type ?? "") | \(r.status ?? "") | \(r.target_count) | \(r.bottle_qty) | \(r.loose_qty) | \(r.is_from_pms) | \(r.is_ndc_verfied) | \(r.is_deleted) | \(r.is_synced) | \(r.rx_no ?? "") | \(r.lot_no ?? "") | \(r.expiry ?? "") | \(r.bucket_id ?? "") | \(r.note ?? "") | \(formatTs(r.created_at)) | \(formatTs(r.updated_at)) |")
        }
        print(sep)
    }

    // MARK: - Transaction Details

    static func printTransactionDetails() {
        let context = CoreDataManager.shared.context
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        let rows = (try? context.fetch(request)) ?? []

        let header = "| detail_id | txn_id | pill_count | type | is_manual | is_deleted | image_path | created_at | updated_at |"
        let sep    = String(repeating: "-", count: header.count)
        print("\n🔍 TRANSACTION DETAILS (\(rows.count) rows)")
        print(sep)
        print(header)
        print(sep)
        for r in rows {
            print("| \(r.txn_details_id) | \(r.txn_id) | \(r.pill_count) | \(r.type ?? "") | \(r.is_manual) | \(r.is_deleted) | \(r.image_path ?? "") | \(formatTs(r.created_at)) | \(formatTs(r.updated_at)) |")
        }
        print(sep)
    }

    // MARK: - Helper

    private static func formatTs(_ ms: Int64) -> String {
        guard ms > 0 else { return "-" }
        return formatDate(Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}
#endif
