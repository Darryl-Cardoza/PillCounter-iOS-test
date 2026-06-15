//
//  LocalDataCleaner.swift
//  PillCounter
//

import CoreData

final class LocalDataCleaner {

    static let shared = LocalDataCleaner()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    func clearAll() {
        let fileManager = FileManager.default

        do {
            print("Clearing ALL local data...")

            TransactionDetailStore.shared.deleteAll()
            TransactionStore.shared.deleteAll()
            BatchStore.shared.deleteAll()
            // NOTE: the drug master (DrugCatalogStore) is intentionally NOT cleared
            // here. It is built up on-device via saveManual(...) as drugs are scanned
            // and is never re-synced from the server, so wiping it would silently lose
            // the whole catalog until every drug is re-scanned. "Clear local data"
            // clears transactions/batches/details/images only.

            // Delete all images
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let files = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
                for fileURL in files {
                    try? fileManager.removeItem(at: fileURL)
                }
                print("All local image files removed.")
            }

            // Reset counters
            UserDefaults.standard.removeObject(forKey: "txnTransactionIdCounter")
            UserDefaults.standard.removeObject(forKey: "txnDetailIdCounter")

            print("All local data cleared successfully.")

        } catch {
            print("Failed to clear local data:", error)
        }
    }
}
