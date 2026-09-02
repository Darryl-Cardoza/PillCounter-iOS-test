//
//  SQLiteCoreDataStack.swift
//  PillCounterTests
//
//  Test fixture helper for suites that exercise TransactionStore /
//  TransactionDetailStore / UserStore / DrugCatalogStore.
//
//  IMPORTANT CAVEAT: those stores are hard-wired to `CoreDataManager.shared`
//  (a `static let`, not injectable via any DI seam), so there is no way to
//  redirect them to a private in-memory Core Data stack from a test target —
//  `CoreDataManager(inMemory:)` exists but nothing in the production stores
//  can be pointed at an instance other than `.shared`. Tests that call
//  `TransactionStore.shared` / `TransactionDetailStore.shared` therefore run
//  against the same on-disk store the app itself would use in the simulator.
//
//  To keep this safe and repeatable:
//   1. Every fixture uses a randomized, large unique Int64 id so it can never
//      collide with real app data or with another test run.
//   2. Every fixture tracks what it created and exposes `cleanUp()`, which
//      hard-deletes the transactions (cascade-deletes details) and the user
//      row. Call it at the end of every test (defer { fixture.cleanUp() }).
//   3. Every fixture holds `sharedCoreDataLock` for its entire
//      init...cleanUp() lifetime — see that constant's doc comment for why
//      `@Suite(.serialized)` alone is not enough.
//

import CoreData
import Foundation
@testable import PillCounter

enum TestIds {
    /// Large randomized id so test fixtures never collide with real app data
    /// (whose auto-increment counters start low) or with parallel test runs.
    static func unique() -> Int64 {
        Int64.random(in: 1_000_000_000...9_000_000_000)
    }
}

/// Cross-suite mutex serializing every fixture in this file (and any ad-hoc
/// block that mutates `AppStorageManager.shared` process globals — see
/// usages in TransactionStoreTests.swift). Swift Testing's `.serialized`
/// trait only serializes tests *within* the `@Suite` it is applied to — it
/// does nothing to stop a different `@Suite` from running concurrently in
/// the same process, which Swift Testing does by default. All of these
/// fixtures share one mutable on-disk Core Data store via
/// `CoreDataManager.shared.context` (a single main-queue-concurrency
/// `NSManagedObjectContext` — see the file-header caveat), plus some stores
/// (`BatchStore`, `StockTxnStore`, and a few `TransactionStore` convenience
/// overloads) key every query off the single process-global
/// `AppStorageManager.shared.userId`. Two fixtures overlapping in time —
/// even from unrelated suites — can corrupt each other's rows, pagination
/// ordering, or "current user" scoping. Holding this one lock for a
/// fixture's entire lifetime makes the whole test target behave as if every
/// suite that touches Core Data were serialized, which is what the original
/// per-suite `.serialized` trait was actually trying to achieve.
let sharedCoreDataLock = NSRecursiveLock()

/// Builds (and tracks for cleanup) the minimal fixture graph a bottle-tracking
/// test needs: a user, a drug, and one or more dispense transactions.
final class BottleTrackingFixture {
    let userId: String
    let user: UserEntity
    let drugId: Int64
    let drug: DrugMasterEntity
    private(set) var txnIds: [Int64] = []
    /// Monotonic per-fixture clock for `created_at`, incremented on every
    /// `makeTransaction()` call — see the doc comment on that method.
    private var nextCreatedAt = Int64(Date().timeIntervalSince1970 * 1000)

    init(drugNdc: String? = nil, isHazardous: Bool? = nil, drugType: String? = nil) {
        sharedCoreDataLock.lock()

        userId = "test-user-\(TestIds.unique())"

        let entity = UserEntity(context: CoreDataManager.shared.context)
        entity.user_id = userId
        entity.created_at = Date()
        CoreDataManager.shared.save(context: CoreDataManager.shared.context)
        user = UserStore.shared.fetchByUserId(userId)!

        drugId = TestIds.unique()
        let ndc = drugNdc ?? "NDC-\(drugId)"
        DrugCatalogStore.shared.saveManual(ndc: ndc, drugId: drugId, drugName: "Test Drug \(drugId)", drugType: drugType, isHazardous: isHazardous)
        drug = DrugCatalogStore.shared.fetchByNdc(ndc)!
    }

    /// `TransactionStore.create` stamps `created_at` from the wall clock in
    /// milliseconds, so a tight loop of `makeTransaction()` calls (as
    /// pagination/ordering tests do) can produce ties — pagination sorts by
    /// `created_at`, so a tie makes offset/limit boundaries and page-vs-page
    /// disjointness non-deterministic. Force-stamp a strictly increasing
    /// `created_at` after each create so ordering is always deterministic.
    @discardableResult
    func makeTransaction(
        isDispense: Bool = true,
        batchId: Int64 = 0,
        isFromPms: Bool = false,
        targetCount: Int32 = 0,
        rxNo: String? = nil,
        bucketId: String? = nil,
        priority: String? = nil,
        refillNo: String? = nil
    ) -> PillCountTransactionEntity {
        let txn = TransactionStore.shared.create(
            for: user,
            drugId: drugId,
            isDispense: isDispense,
            batchId: batchId,
            isFromPms: isFromPms,
            targetCount: targetCount,
            rxNo: rxNo,
            bucketId: bucketId,
            priority: priority,
            refillNo: refillNo
        )
        txnIds.append(txn.txn_id)

        let context = CoreDataManager.shared.context
        context.performAndWait {
            txn.created_at = nextCreatedAt
            CoreDataManager.shared.save(context: context)
        }
        nextCreatedAt += 1

        return txn
    }

    /// Hard-deletes every transaction (and cascade-deleted details) plus the
    /// user row this fixture created, and releases `sharedCoreDataLock`. Call
    /// at the end of every test.
    func cleanUp() {
        for txnId in txnIds {
            TransactionStore.shared.hardDelete(txnId: txnId)
        }
        UserStore.shared.delete(userId: userId)
        sharedCoreDataLock.unlock()
    }
}

/// Builds (and tracks for cleanup) the minimal fixture graph a batch-tracking
/// test needs: a drug, and one or more batches (optionally with stock txns).
/// Takes over `AppStorageManager.shared.userId` for its lifetime (see
/// `sharedCoreDataLock`) and restores the previous value on `cleanUp()`.
final class BatchTrackingFixture {
    let userId: String
    let drugId: Int64
    let drug: DrugMasterEntity
    private let previousUserId: String?
    private(set) var batchIds: [Int64] = []

    init(drugNdc: String? = nil) {
        sharedCoreDataLock.lock()

        userId = "test-user-\(TestIds.unique())"
        previousUserId = AppStorageManager.shared.userId
        AppStorageManager.shared.userId = userId

        drugId = TestIds.unique()
        let ndc = drugNdc ?? "NDC-\(drugId)"
        DrugCatalogStore.shared.saveManual(ndc: ndc, drugId: drugId, drugName: "Test Drug \(drugId)")
        drug = DrugCatalogStore.shared.fetchByNdc(ndc)!
    }

    /// Creates a batch owned by this fixture's user, then force-sets fields
    /// `BatchStore.create`/`updateStatus` don't expose (status, timestamps,
    /// sync/delete flags) directly via Core Data, mirroring how the load-test
    /// generator seeds historical rows.
    @discardableResult
    func makeBatch(
        status: CountStatus = .PARTIAL,
        requestId: String? = nil,
        startTs: Int64? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false
    ) -> BatchCountEntity {
        let batch = BatchStore.shared.create(bucketId: "bucket-\(TestIds.unique())", requestId: requestId)!
        // BatchStore.create derives batch_id from the current millisecond
        // timestamp with no uniqueness constraint in the Core Data model —
        // a tight loop of makeBatch() calls (as pagination tests do) can
        // produce duplicate ids within the same millisecond, silently
        // collapsing what the test expects to be N distinct rows. Force a
        // distinct id here so fixture-created batches never collide.
        batch.batch_id = TestIds.unique()
        batchIds.append(batch.batch_id)

        let context = CoreDataManager.shared.context
        context.performAndWait {
            batch.status = status.rawValue
            if let startTs { batch.start_date_time = startTs }
            batch.is_synced = isSynced
            batch.is_deleted = isDeleted
            CoreDataManager.shared.save(context: context)
        }
        return batch
    }

    @discardableResult
    func makeStockTxn(batch: BatchCountEntity) -> StockTxnEntity {
        StockTxnStore.shared.fetchOrCreate(batch: batch, drugId: drugId, bucketId: batch.bucket_id)
    }

    /// Hard-deletes every batch, its stock txns, and any bottle info rows
    /// hung off those stock txns, plus the drug row this fixture created —
    /// then restores the previous logged-in user id and releases
    /// `sharedCoreDataLock`. Call at the end of every test using this fixture.
    func cleanUp() {
        let context = CoreDataManager.shared.context
        context.performAndWait {
            for batchId in batchIds {
                let batchReq: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
                batchReq.predicate = NSPredicate(format: "batch_id == %lld", batchId)
                if let batch = try? context.fetch(batchReq).first {
                    context.delete(batch)
                }
                let stockReq: NSFetchRequest<StockTxnEntity> = StockTxnEntity.fetchRequest()
                stockReq.predicate = NSPredicate(format: "batch_id == %lld", batchId)
                if let stockTxns = try? context.fetch(stockReq) {
                    for stockTxn in stockTxns {
                        let bottleReq: NSFetchRequest<BottleInfoEntity> = BottleInfoEntity.fetchRequest()
                        bottleReq.predicate = NSPredicate(format: "stock_txn_id == %lld", stockTxn.stock_txn_id)
                        (try? context.fetch(bottleReq))?.forEach { context.delete($0) }
                        context.delete(stockTxn)
                    }
                }
            }
            let drugReq: NSFetchRequest<DrugMasterEntity> = DrugMasterEntity.fetchRequest()
            drugReq.predicate = NSPredicate(format: "drug_id == %lld", drugId)
            if let drugEntity = try? context.fetch(drugReq).first {
                context.delete(drugEntity)
            }
            CoreDataManager.shared.save(context: context)
        }
        AppStorageManager.shared.userId = previousUserId
        sharedCoreDataLock.unlock()
    }
}
