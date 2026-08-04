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
//   3. Suites using this helper are declared `@Suite(.serialized)` since they
//      share one mutable on-disk store and must not run concurrently.
//

import Foundation
@testable import PillCounter

enum TestIds {
    /// Large randomized id so test fixtures never collide with real app data
    /// (whose auto-increment counters start low) or with parallel test runs.
    static func unique() -> Int64 {
        Int64.random(in: 1_000_000_000...9_000_000_000)
    }
}

/// Builds (and tracks for cleanup) the minimal fixture graph a bottle-tracking
/// test needs: a user, a drug, and one or more dispense transactions.
final class BottleTrackingFixture {
    let userId: String
    let user: UserEntity
    let drugId: Int64
    let drug: DrugMasterEntity
    private(set) var txnIds: [Int64] = []

    init(drugNdc: String? = nil) {
        userId = "test-user-\(TestIds.unique())"

        let entity = UserEntity(context: CoreDataManager.shared.context)
        entity.user_id = userId
        entity.created_at = Date()
        CoreDataManager.shared.save(context: CoreDataManager.shared.context)
        user = UserStore.shared.fetchByUserId(userId)!

        drugId = TestIds.unique()
        let ndc = drugNdc ?? "NDC-\(drugId)"
        DrugCatalogStore.shared.saveManual(ndc: ndc, drugId: drugId, drugName: "Test Drug \(drugId)")
        drug = DrugCatalogStore.shared.fetchByNdc(ndc)!
    }

    @discardableResult
    func makeTransaction(isDispense: Bool = true) -> PillCountTransactionEntity {
        let txn = TransactionStore.shared.create(for: user, drugId: drugId, isDispense: isDispense)
        txnIds.append(txn.txn_id)
        return txn
    }

    /// Hard-deletes every transaction (and cascade-deleted details) plus the
    /// user row this fixture created. Call at the end of every test.
    func cleanUp() {
        for txnId in txnIds {
            TransactionStore.shared.hardDelete(txnId: txnId)
        }
        UserStore.shared.delete(userId: userId)
    }
}
