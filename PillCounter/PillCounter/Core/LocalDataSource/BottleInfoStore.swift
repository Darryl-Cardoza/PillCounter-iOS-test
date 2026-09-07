//
//  BottleInfoStore.swift
//  PillCounter
//

import CoreData
import Combine

/// Identity key for a sealed BottleInfoEntity row: (lot_no, exp_no), normalising
/// nil to "" so a missing lot/exp is itself a valid, poolable key.
struct SealedLotKey: Hashable {
    let lotNo: String
    let expNo: String

    init(lotNo: String?, expNo: String?) {
        self.lotNo = lotNo ?? ""
        self.expNo = expNo ?? ""
    }
}

extension BottleInfoEntity {
    /// Sealed heuristic: a sealed row has bottle_qty > 0 and loose_qty == 0.
    var isSealed: Bool { bottle_qty > 0 && loose_qty == 0 }

    var sealedLotKey: SealedLotKey { SealedLotKey(lotNo: lot_no, expNo: exp_no) }

    /// Snapshot image paths captured during open-pill counting for this row,
    /// decoded from `image_paths_json`. Empty for sealed rows and any opened
    /// row with no captured images.
    var imagePaths: [String] { BottleInfoEntity.decodeImagePaths(image_paths_json) }

    static func decodeImagePaths(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func encodeImagePaths(_ paths: [String]) -> String? {
        guard !paths.isEmpty, let data = try? JSONEncoder().encode(paths) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

final class BottleInfoStore {

    static let shared = BottleInfoStore()
    private init() {}

    let bottleInfosDidChange = PassthroughSubject<Void, Never>()

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    // MARK: - Sealed row lookup (heuristic: sealed row has bottle_qty > 0 and loose_qty == 0)
    // Identity key is (stock_txn_id, lot_no, exp_no) — exact match on all three is the
    // same row; any lot OR exp difference is a distinct sealed row. Empty lot/exp ("", "")
    // is itself a valid key, so repeated no-lot-info scans pool into the same row.

    private func fetchSealedRow(stockTxnId: Int64, lotNo: String?, expNo: String?) -> BottleInfoEntity? {
        let targetKey = SealedLotKey(lotNo: lotNo, expNo: expNo)
        return fetchByStockTxn(stockTxnId: stockTxnId).first {
            $0.isSealed && $0.sealedLotKey == targetKey
        }
    }

    /// Sealed bottle_qty for one specific (stockTxnId, lotNo, expNo) row — 0 if that
    /// exact lot/exp has no sealed row yet. Exposed so callers don't hand-filter
    /// `fetchByStockTxn` to reimplement this lookup.
    func sealedBottleQty(stockTxnId: Int64, lotNo: String?, expNo: String?) -> Int32 {
        fetchSealedRow(stockTxnId: stockTxnId, lotNo: lotNo, expNo: expNo)?.bottle_qty ?? 0
    }

    // MARK: - Sealed bottle writes (one row per stock_txn_id + lot_no + exp_no, absolute set)

    @discardableResult
    func setSealedBottleQty(stockTxnId: Int64, bottleQty: Int32, lotNo: String?, expNo: String?) -> BottleInfoEntity? {
        if let existing = fetchSealedRow(stockTxnId: stockTxnId, lotNo: lotNo, expNo: expNo) {
            existing.bottle_qty = bottleQty
            existing.updated_at = nowMs()
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("🧴 [BottleInfoDAO] SET sealed bottle_qty — bottleId: \(existing.bottle_id), stockTxnId: \(stockTxnId), bottleQty: \(bottleQty)")
            bottleInfosDidChange.send()
            return existing
        }

        guard bottleQty > 0 else { return nil }
        guard let stockTxn = StockTxnStore.shared.fetchById(stockTxnId) else { return nil }

        let entity = BottleInfoEntity(context: context)
        entity.bottle_id = generateUniqueId()
        entity.stock_txn_id = stockTxnId
        entity.batch_id = stockTxn.batch_id
        entity.bottle_qty = bottleQty
        entity.loose_qty = 0
        entity.lot_no = lotNo
        entity.exp_no = expNo
        entity.stockTxn = stockTxn

        let now = nowMs()
        entity.created_at = now
        entity.updated_at = now

        CoreDataManager.shared.save(context: context)
        StoreLogger.debug("🧴 [BottleInfoDAO] CREATED sealed row — bottleId: \(entity.bottle_id), stockTxnId: \(stockTxnId), bottleQty: \(bottleQty)")
        bottleInfosDidChange.send()
        return entity
    }

    // MARK: - Opened bottle writes (new row every call)

    /// Same identity key as sealed rows: exact match on (stock_txn_id, lot_no, exp_no)
    /// is the same opened row; any lot OR exp difference is a distinct row. Exposed for
    /// callers (open-pill scan flow) that need to merge into an existing opened row
    /// instead of always inserting a new one — `addOpenedBottle` itself keeps its
    /// existing "always new row" contract for its other call sites.
    func fetchOpenedRow(stockTxnId: Int64, lotNo: String?, expNo: String?) -> BottleInfoEntity? {
        let targetKey = SealedLotKey(lotNo: lotNo, expNo: expNo)
        return fetchByStockTxn(stockTxnId: stockTxnId).first {
            !$0.isSealed && SealedLotKey(lotNo: $0.lot_no, expNo: $0.exp_no) == targetKey
        }
    }

    /// Appends `paths` to an existing opened row's `image_paths_json` array (no-op if
    /// `paths` is empty). Used to merge captured snapshots into a row that was already
    /// merged/updated via `fetchOpenedRow` + `updateOpenedBottleLooseQty`.
    func appendImagePaths(bottleId: Int64, paths: [String]) {
        guard !paths.isEmpty, let bottle = fetchById(bottleId) else { return }
        let merged = bottle.imagePaths + paths
        bottle.image_paths_json = BottleInfoEntity.encodeImagePaths(merged)
        bottle.updated_at = nowMs()
        CoreDataManager.shared.save(context: context)
        bottleInfosDidChange.send()
    }

    @discardableResult
    func addOpenedBottle(
        stockTxnId: Int64, looseQty: Int32, lotNo: String?, expNo: String?, serialNo: String?,
        imagePaths: [String] = []
    ) -> BottleInfoEntity? {
        guard let stockTxn = StockTxnStore.shared.fetchById(stockTxnId) else { return nil }

        let entity = BottleInfoEntity(context: context)
        entity.bottle_id = generateUniqueId()
        entity.stock_txn_id = stockTxnId
        entity.batch_id = stockTxn.batch_id
        entity.bottle_qty = 1
        entity.loose_qty = looseQty
        entity.lot_no = lotNo
        entity.exp_no = expNo
        entity.serial_no = serialNo
        entity.image_paths_json = BottleInfoEntity.encodeImagePaths(imagePaths)
        entity.stockTxn = stockTxn

        let now = nowMs()
        entity.created_at = now
        entity.updated_at = now

        CoreDataManager.shared.save(context: context)
        StoreLogger.debug("🧴 [BottleInfoDAO] CREATED opened row — bottleId: \(entity.bottle_id), stockTxnId: \(stockTxnId), looseQty: \(looseQty)")
        bottleInfosDidChange.send()
        return entity
    }

    func updateOpenedBottleLooseQty(bottleId: Int64, looseQty: Int32) {
        guard let bottle = fetchById(bottleId) else { return }
        bottle.loose_qty = looseQty
        bottle.updated_at = nowMs()
        CoreDataManager.shared.save(context: context)
        StoreLogger.debug("🧴 [BottleInfoDAO] SET opened loose_qty — bottleId: \(bottleId), looseQty: \(looseQty)")
        bottleInfosDidChange.send()
    }

    // MARK: - Read

    func fetchById(_ bottleId: Int64) -> BottleInfoEntity? {
        let request: NSFetchRequest<BottleInfoEntity> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "bottle_id == %lld", bottleId)
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        result.decryptEncryptedFieldsInPlace()
        return result
    }

    func fetchByStockTxn(stockTxnId: Int64) -> [BottleInfoEntity] {
        let request: NSFetchRequest<BottleInfoEntity> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "stock_txn_id == %lld", stockTxnId)
        let results = (try? context.fetch(request)) ?? []
        results.forEach { $0.decryptEncryptedFieldsInPlace() }
        return results
    }

    /// Same as `fetchByStockTxn(stockTxnId:)`, but fetches via an explicit
    /// context — see `StockTxnStore.fetchByBatch(batchId:in:)`.
    func fetchByStockTxn(stockTxnId: Int64, in context: NSManagedObjectContext) -> [BottleInfoEntity] {
        context.performAndWait {
            let request: NSFetchRequest<BottleInfoEntity> = BottleInfoEntity.fetchRequest()
            request.predicate = NSPredicate(format: "stock_txn_id == %lld", stockTxnId)
            let results = (try? context.fetch(request)) ?? []
            results.forEach { $0.decryptEncryptedFieldsInPlace() }
            return results
        }
    }

    func fetchByBatch(batchId: Int64) -> [BottleInfoEntity] {
        let request: NSFetchRequest<BottleInfoEntity> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "batch_id == %lld", batchId)
        let results = (try? context.fetch(request)) ?? []
        results.forEach { $0.decryptEncryptedFieldsInPlace() }
        return results
    }

    // MARK: - Update (edit sheet)

    func setAbsolute(bottleId: Int64, bottleQty: Int32?, looseQty: Int32?) {
        guard let bottle = fetchById(bottleId) else { return }
        if let bottleQty { bottle.bottle_qty = bottleQty }
        if let looseQty { bottle.loose_qty = looseQty }
        bottle.updated_at = nowMs()
        CoreDataManager.shared.save(context: context)
        StoreLogger.debug("🧴 [BottleInfoDAO] SET absolute — bottleId: \(bottleId), bottleQty: \(String(describing: bottleQty)), looseQty: \(String(describing: looseQty))")
        bottleInfosDidChange.send()
    }

    // MARK: - Delete

    func softDelete(bottleId: Int64) {
        let request: NSFetchRequest<NSFetchRequestResult> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "bottle_id == %lld", bottleId)
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            StoreLogger.debug("🧴 [BottleInfoDAO] DELETED — bottleId: \(bottleId)")
            bottleInfosDidChange.send()
        } catch {
            StoreLogger.debug("Failed to delete BottleInfoEntity: \(error)")
        }
    }

    func softDeleteByStockTxn(stockTxnId: Int64) {
        let request: NSFetchRequest<NSFetchRequestResult> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "stock_txn_id == %lld", stockTxnId)
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            StoreLogger.debug("🧴 [BottleInfoDAO] DELETED all rows for stockTxnId: \(stockTxnId)")
        } catch {
            StoreLogger.debug("Failed to delete BottleInfoEntity for stockTxn: \(error)")
        }
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = BottleInfoEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            StoreLogger.debug("🧴 [BottleInfoDAO] DELETED ALL — all bottle info removed")
        } catch {
            StoreLogger.debug("Failed to delete BottleInfoEntity: \(error)")
        }
    }

    // MARK: - Private

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func generateUniqueId() -> Int64 {
        let key = "bottleInfoIdCounter"
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
