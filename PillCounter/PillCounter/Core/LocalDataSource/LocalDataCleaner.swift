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

            TransactionDetailDAO.shared.deleteAll()
            TransactionDAO.shared.deleteAll()
            BatchDAO.shared.deleteAll()
            DrugMasterDAO.shared.deleteAll()

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
