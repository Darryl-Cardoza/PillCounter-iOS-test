//
//  HistoryCleanupDAO.swift
//  PillCounter
//

import CoreData

final class HistoryCleanupStore {

    static let shared = HistoryCleanupStore()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    /// Deletes transactions older than the selected history option.
    /// Also removes associated images from the Document Directory.
    func cleanUpOldHistory() {
        let selectedOption = AppStorageManager.shared.saveHistoryOption

        guard let cutoffDate = selectedOption.getCutoffDate() else { return }
        let cutoffTimestamp = Int64(cutoffDate.timeIntervalSince1970 * 1000)

        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "created_at < %lld", cutoffTimestamp)

        do {
            let oldTransactions = try context.fetch(request)

            if oldTransactions.isEmpty { return }

            for transaction in oldTransactions {

                if let barcodePath = transaction.barcode_image {
                    deleteFileFromDocuments(fileName: barcodePath)
                }

                if let details = transaction.pillCountTransactionDetails
                    as? Set<PillCountTransactionDetailsEntity>
                {
                    for detail in details {
                        if let detailImagePath = detail.image_path {
                            deleteFileFromDocuments(fileName: detailImagePath)
                        }
                    }
                }

                context.delete(transaction)
            }

            CoreDataManager.shared.save(context: context)
            print("🗑️ Cleanup Complete: Deleted \(oldTransactions.count) expired transactions.")

        } catch {
            print("❌ Error cleaning up history: \(error.localizedDescription)")
        }
    }

    private func deleteFileFromDocuments(fileName: String) {
        let fileManager = FileManager.default
        guard let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileUrl = documentsUrl.appendingPathComponent((fileName as NSString).lastPathComponent)
        if fileManager.fileExists(atPath: fileUrl.path) {
            try? fileManager.removeItem(at: fileUrl)
        }
    }
}
