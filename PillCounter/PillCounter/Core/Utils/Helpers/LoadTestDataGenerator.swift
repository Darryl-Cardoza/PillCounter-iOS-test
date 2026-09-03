//
//  LoadTestDataGenerator.swift
//  PillCounter
//
//  Throwaway tooling for the LOAD_TEST scheme only. Bulk-inserts realistic
//  transaction/detail/batch/stock/image data into the SAME on-disk store the
//  app normally uses, so Dashboard/History/Unsynced can be exercised at
//  production-scale volume on a real device. Every row created here carries
//  an id from a reserved high range (see TestIds) so `clearAll()` can find
//  and remove exactly what this generator created, and nothing else.
//

#if LOAD_TEST
import CoreData
import UIKit

enum LoadTestIds {
    /// Reserved id range for load-test data — mirrors the pattern used by
    /// PillCounterTests/Helpers/SQLiteCoreDataStack.swift so generated rows
    /// can never collide with real app data (whose counters start low).
    static let range: ClosedRange<Int64> = 5_000_000_000...5_999_999_999

    static func unique() -> Int64 {
        Int64.random(in: range)
    }

    static func isLoadTestId(_ id: Int64) -> Bool {
        range.contains(id)
    }
}

enum LoadTestDataGenerator {

    struct Progress {
        let created: Int
        let total: Int
    }

    // MARK: - Generate

    /// Bulk-inserts ~10k dispense transactions (proportional detail rows)
    /// plus a proportional set of inventory batches/stock counts, all dated
    /// within today, attached to the currently logged-in user. Runs on a
    /// background context, saving in batches so it doesn't block the main thread.
    static func generate(
        transactionCount: Int = 10_000,
        onProgress: @escaping (Progress) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let userId = AppStorageManager.shared.userId,
              let user = UserStore.shared.fetchByUserId(userId) else {
            completion(.failure(LoadTestError.noLoggedInUser))
            return
        }
        let userObjectId = user.objectID
        // Every generated row's created_at falls within today, spread evenly
        // across the elapsed portion of the day — mirrors real usage (a
        // day's worth of activity), not several days of backdated history.
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let secondsElapsedToday = max(Date().timeIntervalSince(startOfToday), 60)

        DispatchQueue.global(qos: .utility).async {
            let context = CoreDataManager.shared.backgroundContext
            context.perform {
                do {
                    guard let bgUser = try? context.existingObject(with: userObjectId) as? UserEntity else {
                        DispatchQueue.main.async { completion(.failure(LoadTestError.noLoggedInUser)) }
                        return
                    }

                    let drugs = makeDrugs(count: 20, in: context)
                    let detailsPerTxn = 3
                    // A modest pool of distinct encrypted image files, cycled across
                    // rows. Still exercises real per-row disk I/O/decrypt during
                    // scroll testing, without paying JPEG-encode + AES-GCM-seal +
                    // encrypted-disk-write cost 30k times, which is what stalled the
                    // generator (no time to breathe -> watchdog/jetsam kill).
                    let imagePool: [String] = (0..<50).compactMap { _ in autoreleasepool { makeFakeImageFile() } }

                    func randomTimestampToday() -> Int64 {
                        let offset = TimeInterval.random(in: 0...secondsElapsedToday)
                        return Int64(startOfToday.addingTimeInterval(offset).timeIntervalSince1970 * 1000)
                    }

                    var createdTxns = 0
                    var pendingCount = 0

                    for i in 0..<transactionCount {
                        try autoreleasepool {
                            let txn = PillCountTransactionEntity(context: context)
                            let txnId = LoadTestIds.unique()
                            let drug = drugs[i % drugs.count]

                            txn.txn_id = txnId
                            txn.local_id = txnId
                            txn.is_dispense = true
                            txn.is_deleted = false
                            txn.is_from_pms = false
                            txn.is_ndc_verfied = true
                            txn.is_synced = i % 5 != 0 // ~20% unsynced, matches real mixed state
                            txn.status = randomStatus()
                            txn.rx_no = "LT-RX-\(txnId)"
                            txn.patient_name = "Load Test Patient \(i)"
                            txn.drug_id = drug.drug_id
                            txn.target_count = Int32.random(in: 10...200)
                            txn.batch_id = 0
                            txn.bucket_id = "load-test"
                            let createdAt = randomTimestampToday()
                            txn.created_at = createdAt
                            txn.updated_at = createdAt
                            txn.drug = drug
                            txn.user = bgUser

                            for d in 0..<detailsPerTxn {
                                let detail = PillCountTransactionDetailsEntity(context: context)
                                detail.txn_details_id = LoadTestIds.unique()
                                detail.txn_id = txnId
                                detail.pill_count = Int32.random(in: 1...50)
                                detail.type = d == 0 ? "initial" : "recount"
                                detail.is_manual = false
                                detail.is_deleted = false
                                detail.created_at = txn.created_at
                                detail.updated_at = txn.created_at
                                detail.image_path = imagePool.randomElement()
                                detail.pillCountTransaction = txn
                            }

                            createdTxns += 1
                            pendingCount += 1

                            if pendingCount >= 200 {
                                try context.save()
                                pendingCount = 0
                                let progress = createdTxns
                                DispatchQueue.main.async {
                                    onProgress(Progress(created: progress, total: transactionCount))
                                }
                            }
                        }
                    }

                    // Inventory side (Regular Count / Dashboard's "inventory" queue,
                    // History's batch/stock tab) — real BatchCountEntity/StockTxnEntity/
                    // BottleInfoEntity rows, not just dispense transactions. Proportional
                    // to the dispense volume: ~1 batch per 40 dispense txns, a handful
                    // of NDCs (stock txns) per batch.
                    let batchCount = max(1, transactionCount / 40)

                    for b in 0..<batchCount {
                        try autoreleasepool {
                            let batch = BatchCountEntity(context: context)
                            let batchId = LoadTestIds.unique()
                            batch.batch_id = batchId
                            batch.user_id = userId
                            batch.user_name = bgUser.fname
                            batch.bucket_id = "load-test"
                            batch.status = randomStatus()
                            batch.is_deleted = false
                            batch.is_synced = b % 5 != 0
                            let startTs = randomTimestampToday()
                            batch.start_date_time = startTs
                            batch.end_date_time = startTs
                            batch.total_ndcs = Int16.random(in: 1...10)

                            let ndcCount = Int.random(in: 1...5)
                            for _ in 0..<ndcCount {
                                let drug = drugs[Int.random(in: 0..<drugs.count)]
                                let stockTxn = StockTxnEntity(context: context)
                                let stockTxnId = LoadTestIds.unique()
                                stockTxn.stock_txn_id = stockTxnId
                                stockTxn.batch_id = batchId
                                stockTxn.bucket_id = "load-test"
                                stockTxn.drug_id = drug.drug_id
                                stockTxn.drug = drug
                                stockTxn.is_deleted = false
                                stockTxn.status = randomStatus()
                                stockTxn.batch = batch

                                let bottle = BottleInfoEntity(context: context)
                                bottle.bottle_id = LoadTestIds.unique()
                                bottle.stock_txn_id = stockTxnId
                                bottle.batch_id = batchId
                                bottle.bottle_qty = Int32.random(in: 10...200)
                                bottle.lot_no = "LT-LOT-\(stockTxnId)"
                                bottle.created_at = startTs
                                bottle.updated_at = startTs
                                bottle.stockTxn = stockTxn
                            }

                            pendingCount += 1
                            if pendingCount >= 100 {
                                try context.save()
                                pendingCount = 0
                            }
                        }
                    }

                    if context.hasChanges {
                        try context.save()
                    }

                    DispatchQueue.main.async {
                        onProgress(Progress(created: transactionCount, total: transactionCount))
                        completion(.success(()))
                    }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    // MARK: - Clear

    /// Deletes every row this generator created (identified by the reserved
    /// id range) plus their generated image files. Leaves real app data untouched.
    static func clearAll(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let context = CoreDataManager.shared.backgroundContext
            context.perform {
                do {
                    let txnRequest: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
                    txnRequest.predicate = NSPredicate(
                        format: "txn_id >= %lld AND txn_id <= %lld",
                        LoadTestIds.range.lowerBound, LoadTestIds.range.upperBound
                    )
                    let txns = try context.fetch(txnRequest)
                    var imageFileNames = Set<String>()
                    for txn in txns {
                        let details = txn.pillCountTransactionDetails as? Set<PillCountTransactionDetailsEntity> ?? []
                        details.forEach { if let path = $0.image_path { imageFileNames.insert(path) } }
                        context.delete(txn) // cascades to details
                    }

                    let drugRequest: NSFetchRequest<DrugMasterEntity> = DrugMasterEntity.fetchRequest()
                    drugRequest.predicate = NSPredicate(
                        format: "drug_id >= %lld AND drug_id <= %lld",
                        LoadTestIds.range.lowerBound, LoadTestIds.range.upperBound
                    )
                    let drugs = try context.fetch(drugRequest)
                    for drug in drugs {
                        if let path = drug.drug_image { imageFileNames.insert(path) }
                        context.delete(drug)
                    }

                    // Inventory side — batches cascade-delete their stock txns,
                    // which cascade-delete their bottle infos (per the model's
                    // Cascade delete rules), so deleting the batch is enough.
                    let batchRequest: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
                    batchRequest.predicate = NSPredicate(
                        format: "batch_id >= %lld AND batch_id <= %lld",
                        LoadTestIds.range.lowerBound, LoadTestIds.range.upperBound
                    )
                    let batches = try context.fetch(batchRequest)
                    for batch in batches {
                        context.delete(batch)
                    }

                    if context.hasChanges {
                        try context.save()
                    }

                    deleteImageFiles(named: imageFileNames)

                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    // MARK: - Drugs

    private static func makeDrugs(count: Int, in context: NSManagedObjectContext) -> [DrugMasterEntity] {
        (0..<count).map { i -> DrugMasterEntity in
            let drug = DrugMasterEntity(context: context)
            let drugId = LoadTestIds.unique()
            drug.drug_id = drugId
            drug.ndc = "LT-NDC-\(drugId)"
            drug.drug_name = "Load Test Drug \(i)"
            drug.drug_type = "tablet"
            drug.strength = "10mg"
            drug.dosage_form = "tablet"
            drug.package_qty = 100
            drug.is_hazardous = false
            drug.drug_image = makeFakeImageFile()
            drug.created_at = Int64(Date().timeIntervalSince1970 * 1000)
            return drug
        }
    }

    // MARK: - Status mix

    /// Real transactions accumulate as a mix, not all completed — mirrors
    /// that so History's status filters actually have data to filter over.
    private static func randomStatus() -> String {
        switch Int.random(in: 0..<100) {
        case 0..<59: return CountStatus.COMPLETED.rawValue
        case 59..<99: return CountStatus.PARTIAL.rawValue
        default: return CountStatus.ON_HOLD.rawValue
        }
    }

    // MARK: - Images

    /// Generates a small solid-color placeholder image and saves it through
    /// PhotoFileManager (same AES-GCM-encrypted convention real photos use),
    /// so the stored path decrypts and loads exactly like a real captured photo.
    private static func makeFakeImageFile() -> String? {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(
                hue: CGFloat.random(in: 0...1), saturation: 0.6, brightness: 0.8, alpha: 1
            ).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return PhotoFileManager.shared.saveImage(image)
    }

    /// Fake images are written through PhotoFileManager into the app's flat
    /// Documents directory alongside real photos (no dedicated subfolder), so
    /// cleanup removes them individually by the filename each deleted row held.
    private static func deleteImageFiles(named fileNames: Set<String>) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for name in fileNames {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
        }
    }

    enum LoadTestError: LocalizedError {
        case noLoggedInUser

        var errorDescription: String? {
            switch self {
            case .noLoggedInUser:
                return "No logged-in user found — log in before generating load test data."
            }
        }
    }
}
#endif
