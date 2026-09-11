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

/// One snapshot captured during open-pill counting: the file path plus the pill
/// count at the moment of that specific Add tap (not the row's running total —
/// see BottleInfoEntity.images).
struct BottleImageRecord: Codable, Equatable {
    let path: String
    let count: Int32
}

extension BottleInfoEntity {
    /// Sealed heuristic: a sealed row has bottle_qty > 0 and loose_qty == 0.
    var isSealed: Bool { bottle_qty > 0 && loose_qty == 0 }

    /// A row zeroed out (e.g. edited/pruned down to nothing) carries no sealed-vs-opened
    /// identity anymore — isSealed reads false for it same as a genuine opened row counted
    /// at 0 loose pills, so callers matching by lot/exp normally treat it as reclaimable by
    /// either kind. serial_no/images are only ever written by addOpenedBottle (setSealedBottleQty
    /// never touches them) — their presence means this 0/0 row is a real counted-empty opened
    /// bottle, not a pruned one, so it must NOT be reclaimed as a sealed row. This is a
    /// best-effort signal, not a full fix: an opened scan with no serial and no images still
    /// collides with a pruned row indistinguishably.
    var isEmpty: Bool { bottle_qty == 0 && loose_qty == 0 && serial_no == nil && images.isEmpty }

    var sealedLotKey: SealedLotKey { SealedLotKey(lotNo: lot_no, expNo: exp_no) }

    /// Snapshots captured during open-pill counting for this row, decoded from
    /// `image_paths_json`. Empty for sealed rows and any opened row with no
    /// captured images.
    var images: [BottleImageRecord] { BottleInfoEntity.decodeImages(image_paths_json) }

    static func decodeImages(_ json: String?) -> [BottleImageRecord] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([BottleImageRecord].self, from: data)) ?? []
    }

    static func encodeImages(_ images: [BottleImageRecord]) -> String? {
        guard !images.isEmpty, let data = try? JSONEncoder().encode(images) else { return nil }
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
            ($0.isSealed || $0.isEmpty) && $0.sealedLotKey == targetKey
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
        setSealedBottleQtyTracked(stockTxnId: stockTxnId, bottleQty: bottleQty, lotNo: lotNo, expNo: expNo).entity
    }

    /// Same as `setSealedBottleQty`, but also reports whether this call inserted a fresh
    /// row (vs merging into one that already existed) — callers that track "did this
    /// session actually create a row" (e.g. Cancel eligibility) must use this signal
    /// rather than re-deriving it from bottle_qty == 0, which reads the same for "no row"
    /// and "existing row zeroed out". A distinct name (not an overload) avoids ambiguity
    /// at every existing call site that discards the result via `if let`.
    func setSealedBottleQtyTracked(
        stockTxnId: Int64, bottleQty: Int32, lotNo: String?, expNo: String?
    ) -> (entity: BottleInfoEntity?, created: Bool) {
        if let existing = fetchSealedRow(stockTxnId: stockTxnId, lotNo: lotNo, expNo: expNo) {
            existing.bottle_qty = bottleQty
            existing.updated_at = nowMs()
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("🧴 [BottleInfoDAO] SET sealed bottle_qty — bottleId: \(existing.bottle_id), stockTxnId: \(stockTxnId), bottleQty: \(bottleQty)")
            bottleInfosDidChange.send()
            return (existing, false)
        }

        guard bottleQty > 0 else { return (nil, false) }
        guard let stockTxn = StockTxnStore.shared.fetchById(stockTxnId) else { return (nil, false) }

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
        return (entity, true)
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

    /// Appends `images` to an existing opened row's `image_paths_json` array (no-op if
    /// `images` is empty). Used to merge captured snapshots into a row that was already
    /// merged/updated via `fetchOpenedRow` + `updateOpenedBottleLooseQty`.
    func appendImages(bottleId: Int64, images: [BottleImageRecord]) {
        guard !images.isEmpty, let bottle = fetchById(bottleId) else { return }
        let merged = bottle.images + images
        bottle.image_paths_json = BottleInfoEntity.encodeImages(merged)
        bottle.updated_at = nowMs()
        CoreDataManager.shared.save(context: context)
        bottleInfosDidChange.send()
    }

    /// Reclaims a zeroed row at the same (stockTxnId, lot, exp) key rather than always
    /// inserting: a lot pruned down to 0/0 (edit) or zeroed out (pill-count correction)
    /// has no remaining sealed-vs-opened identity, so re-scanning it as opened should
    /// reuse that row exactly like the sealed write path already does — otherwise a
    /// re-scan of a zeroed lot leaves the old 0/0 row plus a new one.
    @discardableResult
    func addOpenedBottle(
        stockTxnId: Int64, looseQty: Int32, lotNo: String?, expNo: String?, serialNo: String?,
        images: [BottleImageRecord] = []
    ) -> BottleInfoEntity? {
        addOpenedBottleTracked(
            stockTxnId: stockTxnId, looseQty: looseQty, lotNo: lotNo, expNo: expNo,
            serialNo: serialNo, images: images
        ).entity
    }

    /// Same as `addOpenedBottle`, but also reports whether this call inserted a fresh
    /// row vs reclaimed a zeroed one — see `setSealedBottleQtyTracked`'s doc for why
    /// callers tracking Cancel-eligibility need this signal instead of an overload.
    func addOpenedBottleTracked(
        stockTxnId: Int64, looseQty: Int32, lotNo: String?, expNo: String?, serialNo: String?,
        images: [BottleImageRecord] = []
    ) -> (entity: BottleInfoEntity?, created: Bool) {
        guard let stockTxn = StockTxnStore.shared.fetchById(stockTxnId) else { return (nil, false) }

        let targetKey = SealedLotKey(lotNo: lotNo, expNo: expNo)
        if let existing = fetchByStockTxn(stockTxnId: stockTxnId).first(where: {
            $0.isEmpty && $0.sealedLotKey == targetKey
        }) {
            existing.loose_qty = looseQty
            existing.serial_no = serialNo
            existing.image_paths_json = BottleInfoEntity.encodeImages(images)
            existing.updated_at = nowMs()
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("🧴 [BottleInfoDAO] REUSED zeroed row as opened — bottleId: \(existing.bottle_id), stockTxnId: \(stockTxnId), looseQty: \(looseQty)")
            bottleInfosDidChange.send()
            return (existing, false)
        }

        let entity = BottleInfoEntity(context: context)
        entity.bottle_id = generateUniqueId()
        entity.stock_txn_id = stockTxnId
        entity.batch_id = stockTxn.batch_id
        // An opened row is not a bottle count — 0 keeps isSealed's
        // (bottle_qty > 0 && loose_qty == 0) heuristic correct even when
        // looseQty is 0 (bottle opened, counted empty).
        entity.bottle_qty = 0
        entity.loose_qty = looseQty
        entity.lot_no = lotNo
        entity.exp_no = expNo
        entity.serial_no = serialNo
        entity.image_paths_json = BottleInfoEntity.encodeImages(images)
        entity.stockTxn = stockTxn

        let now = nowMs()
        entity.created_at = now
        entity.updated_at = now

        CoreDataManager.shared.save(context: context)
        StoreLogger.debug("🧴 [BottleInfoDAO] CREATED opened row — bottleId: \(entity.bottle_id), stockTxnId: \(stockTxnId), looseQty: \(looseQty)")
        bottleInfosDidChange.send()
        return (entity, true)
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

    /// NSBatchDeleteRequest bypasses `context`'s object graph and can collide with an
    /// unrelated save in flight on the same context ("Could not merge changes", silently
    /// swallowed) — delete through the context instead so removal is part of its normal save cycle.
    ///
    /// Returns whether the delete actually persisted — `save` alone swallows the error,
    /// so a caller that reacts to "row is gone" (e.g. pruning the parent StockTxn once its
    /// last bottle row is deleted) must not treat a failed save as a successful delete.
    @discardableResult
    func softDelete(bottleId: Int64) -> Bool {
        let request: NSFetchRequest<BottleInfoEntity> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "bottle_id == %lld", bottleId)
        do {
            guard let bottle = try context.fetch(request).first else { return false }
            context.delete(bottle)
            guard CoreDataManager.shared.saveReturningSuccess(context: context) else { return false }
            StoreLogger.debug("🧴 [BottleInfoDAO] DELETED — bottleId: \(bottleId)")
            bottleInfosDidChange.send()
            return true
        } catch {
            StoreLogger.debug("Failed to delete BottleInfoEntity: \(error)")
            return false
        }
    }

    @discardableResult
    func softDeleteByStockTxn(stockTxnId: Int64) -> Bool {
        let request: NSFetchRequest<BottleInfoEntity> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "stock_txn_id == %lld", stockTxnId)
        do {
            let bottles = try context.fetch(request)
            guard !bottles.isEmpty else { return true }
            bottles.forEach { context.delete($0) }
            guard CoreDataManager.shared.saveReturningSuccess(context: context) else { return false }
            StoreLogger.debug("🧴 [BottleInfoDAO] DELETED all rows for stockTxnId: \(stockTxnId)")
            return true
        } catch {
            StoreLogger.debug("Failed to delete BottleInfoEntity for stockTxn: \(error)")
            return false
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
