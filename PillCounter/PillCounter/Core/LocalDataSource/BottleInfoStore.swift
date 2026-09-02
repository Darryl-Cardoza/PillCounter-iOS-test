//
//  BottleInfoStore.swift
//  PillCounter
//

import CoreData
import Combine

final class BottleInfoStore {

    static let shared = BottleInfoStore()
    private init() {}

    let bottleInfosDidChange = PassthroughSubject<Void, Never>()

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    // MARK: - Sealed row lookup (heuristic: sealed row has bottle_qty > 0 and loose_qty == 0)

    private func fetchSealedRow(stockTxnId: Int64) -> BottleInfoEntity? {
        fetchByStockTxn(stockTxnId: stockTxnId).first { $0.bottle_qty > 0 && $0.loose_qty == 0 }
    }

    // MARK: - Sealed bottle writes (single row per StockTxn, absolute set)

    @discardableResult
    func setSealedBottleQty(stockTxnId: Int64, bottleQty: Int32, lotNo: String?, expNo: String?) -> BottleInfoEntity? {
        if let existing = fetchSealedRow(stockTxnId: stockTxnId) {
            existing.bottle_qty = bottleQty
            if let lotNo { existing.lot_no = lotNo }
            if let expNo { existing.exp_no = expNo }
            existing.updated_at = nowMs()
            CoreDataManager.shared.save(context: context)
            print("🧴 [BottleInfoDAO] SET sealed bottle_qty — bottleId: \(existing.bottle_id), stockTxnId: \(stockTxnId), bottleQty: \(bottleQty)")
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
        print("🧴 [BottleInfoDAO] CREATED sealed row — bottleId: \(entity.bottle_id), stockTxnId: \(stockTxnId), bottleQty: \(bottleQty)")
        bottleInfosDidChange.send()
        return entity
    }

    // MARK: - Opened bottle writes (new row every call)

    @discardableResult
    func addOpenedBottle(stockTxnId: Int64, looseQty: Int32, lotNo: String?, expNo: String?, serialNo: String?) -> BottleInfoEntity? {
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
        entity.stockTxn = stockTxn

        let now = nowMs()
        entity.created_at = now
        entity.updated_at = now

        CoreDataManager.shared.save(context: context)
        print("🧴 [BottleInfoDAO] CREATED opened row — bottleId: \(entity.bottle_id), stockTxnId: \(stockTxnId), looseQty: \(looseQty)")
        bottleInfosDidChange.send()
        return entity
    }

    func updateOpenedBottleLooseQty(bottleId: Int64, looseQty: Int32) {
        guard let bottle = fetchById(bottleId) else { return }
        bottle.loose_qty = looseQty
        bottle.updated_at = nowMs()
        CoreDataManager.shared.save(context: context)
        print("🧴 [BottleInfoDAO] SET opened loose_qty — bottleId: \(bottleId), looseQty: \(looseQty)")
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
        print("🧴 [BottleInfoDAO] SET absolute — bottleId: \(bottleId), bottleQty: \(String(describing: bottleQty)), looseQty: \(String(describing: looseQty))")
        bottleInfosDidChange.send()
    }

    // MARK: - Delete

    func softDelete(bottleId: Int64) {
        let request: NSFetchRequest<NSFetchRequestResult> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "bottle_id == %lld", bottleId)
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            print("🧴 [BottleInfoDAO] DELETED — bottleId: \(bottleId)")
            bottleInfosDidChange.send()
        } catch {
            print("Failed to delete BottleInfoEntity: \(error)")
        }
    }

    func softDeleteByStockTxn(stockTxnId: Int64) {
        let request: NSFetchRequest<NSFetchRequestResult> = BottleInfoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "stock_txn_id == %lld", stockTxnId)
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            print("🧴 [BottleInfoDAO] DELETED all rows for stockTxnId: \(stockTxnId)")
        } catch {
            print("Failed to delete BottleInfoEntity for stockTxn: \(error)")
        }
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = BottleInfoEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            print("🧴 [BottleInfoDAO] DELETED ALL — all bottle info removed")
        } catch {
            print("Failed to delete BottleInfoEntity: \(error)")
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
