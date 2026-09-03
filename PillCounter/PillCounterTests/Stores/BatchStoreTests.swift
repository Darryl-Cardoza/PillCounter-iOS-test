//
//  BatchStoreTests.swift
//  PillCounterTests
//
//  Tests for BatchStore. Runs against the real on-disk CoreData store (see
//  SQLiteCoreDataStack.swift for why); every fixture is uniquely-id'd and
//  torn down at the end of each test. BatchStore scopes every query to
//  AppStorageManager.shared.userId, so BatchTrackingFixture takes over that
//  keychain value for its lifetime — see its doc comment.
//

import CoreData
import Testing
@testable import PillCounter

@Suite(.serialized)
struct BatchStoreTests {

    // MARK: - create

    @Test func createReturnsPersistedBatchWithDefaults() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }

        let batch = fixture.makeBatch() // uses BatchStore.shared.create under the hood and tracks it for cleanup.
        #expect(batch.status == CountStatus.PARTIAL.rawValue) // makeBatch re-applies .PARTIAL; asserting create's own default here too.
        #expect(batch.is_deleted == false)
        #expect(batch.user_id == fixture.userId)

        let created = BatchStore.shared.create(bucketId: "bucket-1", requestId: "req-1")
        #expect(created != nil)
        #expect(created?.status == CountStatus.PARTIAL.rawValue)
        #expect(created?.is_deleted == false)
        #expect(created?.is_synced == false)
        #expect(created?.bucket_id == "bucket-1")
        #expect(created?.req_id_from_pms == "req-1")
        #expect(created?.user_id == fixture.userId)
        if let created {
            BatchStore.shared.softDelete(ids: [created.batch_id]) // clean up the row created outside the fixture's tracking.
        }
    }

    @Test func createReturnsNilWhenNoUserLoggedIn() {
        let previousUserId = AppStorageManager.shared.userId
        AppStorageManager.shared.userId = nil
        defer { AppStorageManager.shared.userId = previousUserId }

        #expect(BatchStore.shared.create(bucketId: "bucket-x") == nil)
    }

    // MARK: - fetchById

    @Test func fetchByIdReturnsMatchingUndeletedBatch() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()

        let result = BatchStore.shared.fetchById(batch.batch_id)
        #expect(result?.batch_id == batch.batch_id)
    }

    @Test func fetchByIdReturnsNilForDeletedBatch() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch(isDeleted: true)

        #expect(BatchStore.shared.fetchById(batch.batch_id) == nil)
    }

    @Test func fetchByIdReturnsNilForNonexistentBatch() {
        #expect(BatchStore.shared.fetchById(-999_999) == nil)
    }

    @Test func fetchByIdInContextMatchesDefaultContextResult() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()

        let context = CoreDataManager.shared.context
        let result = BatchStore.shared.fetchById(batch.batch_id, in: context)
        #expect(result?.batch_id == batch.batch_id)
    }

    // MARK: - fetchAll

    @Test func fetchAllReturnsOnlyCurrentUsersBatchesIncludingDeleted() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let active = fixture.makeBatch()
        let deleted = fixture.makeBatch(isDeleted: true)

        let results = BatchStore.shared.fetchAll()
        let ids = Set(results.map { $0.batch_id })
        #expect(ids.contains(active.batch_id))
        #expect(ids.contains(deleted.batch_id)) // fetchAll has no is_deleted filter, unlike fetchAllPartial/Completed.
    }

    // MARK: - fetchAllPartial / fetchAllPartial(in:) / fetchAllPartialPage

    @Test func fetchAllPartialReturnsOnlyPartialUndeletedNewestFirst() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let older = fixture.makeBatch(status: .PARTIAL, startTs: 1000)
        let newer = fixture.makeBatch(status: .PARTIAL, startTs: 2000)
        let completed = fixture.makeBatch(status: .COMPLETED)
        let deleted = fixture.makeBatch(status: .PARTIAL, isDeleted: true)

        let results = BatchStore.shared.fetchAllPartial()
        #expect(results.map { $0.batch_id } == [newer.batch_id, older.batch_id])
        let ids = Set(results.map { $0.batch_id })
        #expect(!ids.contains(completed.batch_id))
        #expect(!ids.contains(deleted.batch_id))
    }

    @Test func fetchAllPartialInContextMatchesDefaultContextResult() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .PARTIAL)

        let context = CoreDataManager.shared.context
        let viaContext = BatchStore.shared.fetchAllPartial(in: context)
        let viaDefault = BatchStore.shared.fetchAllPartial()
        #expect(Set(viaContext.map { $0.batch_id }) == Set(viaDefault.map { $0.batch_id }))
    }

    @Test func fetchAllPartialPageRespectsLimitAndOffset() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        for i in 0..<5 { fixture.makeBatch(status: .PARTIAL, startTs: Int64(i * 1000)) }

        let page1 = BatchStore.shared.fetchAllPartialPage(limit: 2, offset: 0)
        let page2 = BatchStore.shared.fetchAllPartialPage(limit: 2, offset: 2)
        let page3 = BatchStore.shared.fetchAllPartialPage(limit: 2, offset: 4)

        #expect(page1.count == 2)
        #expect(page2.count == 2)
        #expect(page3.count == 1)
        let allIds = Set(page1.map { $0.batch_id } + page2.map { $0.batch_id } + page3.map { $0.batch_id })
        #expect(allIds.count == 5)
    }

    // MARK: - fetchAllCompleted / fetchAllCompletedPage

    @Test func fetchAllCompletedReturnsOnlyCompletedUndeleted() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let completed = fixture.makeBatch(status: .COMPLETED)
        let partial = fixture.makeBatch(status: .PARTIAL)

        let results = BatchStore.shared.fetchAllCompleted()
        let ids = Set(results.map { $0.batch_id })
        #expect(ids.contains(completed.batch_id))
        #expect(!ids.contains(partial.batch_id))
    }

    @Test func fetchAllCompletedPageRespectsLimitAndOffset() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        for i in 0..<3 { fixture.makeBatch(status: .COMPLETED, startTs: Int64(i * 1000)) }

        let page1 = BatchStore.shared.fetchAllCompletedPage(limit: 2, offset: 0)
        let page2 = BatchStore.shared.fetchAllCompletedPage(limit: 2, offset: 2)
        #expect(page1.count == 2)
        #expect(page2.count == 1)
    }

    // MARK: - fetchLastCreated

    @Test func fetchLastCreatedReturnsMostRecentPartialBatch() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .PARTIAL, startTs: 1000)
        let newest = fixture.makeBatch(status: .PARTIAL, startTs: 5000)
        fixture.makeBatch(status: .COMPLETED, startTs: 9000)

        #expect(BatchStore.shared.fetchLastCreated()?.batch_id == newest.batch_id)
    }

    @Test func fetchLastCreatedReturnsNilWhenNoPartialBatches() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .COMPLETED)

        #expect(BatchStore.shared.fetchLastCreated() == nil)
    }

    // MARK: - fetchByDateRange / fetchByDateRange(in:) / fetchByDateRangePage

    @Test func fetchByDateRangeReturnsOnlyRowsInsideBoundsInclusive() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let inRange = fixture.makeBatch(startTs: 5000)
        let before = fixture.makeBatch(startTs: 1000)
        let after = fixture.makeBatch(startTs: 9000)

        let results = BatchStore.shared.fetchByDateRange(startTs: 5000, endTs: 5000)
        let ids = Set(results.map { $0.batch_id })
        #expect(ids.contains(inRange.batch_id))
        #expect(!ids.contains(before.batch_id))
        #expect(!ids.contains(after.batch_id))
    }

    @Test func fetchByDateRangeInContextMatchesDefaultContextResult() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(startTs: 3000)

        let context = CoreDataManager.shared.context
        let viaContext = BatchStore.shared.fetchByDateRange(startTs: 0, endTs: 10_000, in: context)
        let viaDefault = BatchStore.shared.fetchByDateRange(startTs: 0, endTs: 10_000)
        #expect(Set(viaContext.map { $0.batch_id }) == Set(viaDefault.map { $0.batch_id }))
    }

    @Test func fetchByDateRangePageRespectsLimitAndOffset() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        for i in 0..<4 { fixture.makeBatch(startTs: Int64(i * 1000)) }

        let page1 = BatchStore.shared.fetchByDateRangePage(startTs: 0, endTs: 10_000, limit: 3, offset: 0)
        let page2 = BatchStore.shared.fetchByDateRangePage(startTs: 0, endTs: 10_000, limit: 3, offset: 3)
        #expect(page1.count == 3)
        #expect(page2.count == 1)
    }

    // MARK: - fetchCompletedUnsynced / fetchCompletedUnsyncedPage

    @Test func fetchCompletedUnsyncedReturnsOnlyCompletedAndUnsynced() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let matching = fixture.makeBatch(status: .COMPLETED, isSynced: false)
        let synced = fixture.makeBatch(status: .COMPLETED, isSynced: true)
        let partial = fixture.makeBatch(status: .PARTIAL, isSynced: false)

        let results = BatchStore.shared.fetchCompletedUnsynced()
        let ids = Set(results.map { $0.batch_id })
        #expect(ids.contains(matching.batch_id))
        #expect(!ids.contains(synced.batch_id))
        #expect(!ids.contains(partial.batch_id))
    }

    @Test func fetchCompletedUnsyncedPageRespectsLimitAndOffset() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        for i in 0..<3 { fixture.makeBatch(status: .COMPLETED, startTs: Int64(i * 1000), isSynced: false) }

        let page1 = BatchStore.shared.fetchCompletedUnsyncedPage(limit: 2, offset: 0)
        let page2 = BatchStore.shared.fetchCompletedUnsyncedPage(limit: 2, offset: 2)
        #expect(page1.count == 2)
        #expect(page2.count == 1)
    }

    // MARK: - fetchCompletedUnsyncedPage(after:limit:) — keyset pagination

    @Test func fetchCompletedUnsyncedPageAfterReturnsFirstPageWhenCursorNil() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batches = (0..<3).map { fixture.makeBatch(status: .COMPLETED, startTs: Int64($0 * 1000), isSynced: false) }

        let page = BatchStore.shared.fetchCompletedUnsyncedPage(after: nil, limit: 2)
        #expect(page.map { $0.batch_id } == [batches[0].batch_id, batches[1].batch_id])
    }

    /// The bug this method exists to fix: with OFFSET-based paging, marking
    /// a row synced BETWEEN page fetches shifts every later row's position
    /// back by one, so the next OFFSET-anchored page silently skips a row.
    /// Keyset pagination (anchored on `start_date_time`, which never
    /// changes) must not exhibit this.
    @Test func fetchCompletedUnsyncedPageAfterDoesNotSkipRowsSyncedMidDrain() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batches = (0..<4).map { fixture.makeBatch(status: .COMPLETED, startTs: Int64($0 * 1000), isSynced: false) }

        let firstPage = BatchStore.shared.fetchCompletedUnsyncedPage(after: nil, limit: 2)
        #expect(firstPage.map { $0.batch_id } == [batches[0].batch_id, batches[1].batch_id])

        BatchStore.shared.markSynced(batchId: batches[0].batch_id)

        let secondPage = BatchStore.shared.fetchCompletedUnsyncedPage(after: firstPage.last!.start_date_time, limit: 2)
        #expect(secondPage.map { $0.batch_id } == [batches[2].batch_id, batches[3].batch_id])
    }

    // MARK: - countByDateRange

    @Test func countByDateRangeMatchesFetchCount() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        for i in 0..<3 { fixture.makeBatch(startTs: Int64(i * 1000)) }

        let count = BatchStore.shared.countByDateRange(startTs: 0, endTs: 10_000, status: nil)
        #expect(count == 3)
    }

    @Test func countByDateRangeFiltersByStatusWhenGiven() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .COMPLETED, startTs: 1000)
        fixture.makeBatch(status: .PARTIAL, startTs: 2000)

        let completedCount = BatchStore.shared.countByDateRange(startTs: 0, endTs: 10_000, status: .COMPLETED)
        let partialCount = BatchStore.shared.countByDateRange(startTs: 0, endTs: 10_000, status: .PARTIAL)
        #expect(completedCount == 1)
        #expect(partialCount == 1)
    }

    // MARK: - countPendingInventory

    @Test func countPendingInventoryFacetsPartitionAllPartial() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .PARTIAL, requestId: "req-1")
        fixture.makeBatch(status: .PARTIAL, requestId: nil)

        let cycleCount = BatchStore.shared.countPendingInventory(facet: .cycleCount)
        let pendingBatch = BatchStore.shared.countPendingInventory(facet: .pendingBatch)
        #expect(cycleCount + pendingBatch == 2)
    }

    @Test func countPendingInventoryCycleCountFacetRequiresNonEmptyRequestId() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .PARTIAL, requestId: "req-1")
        fixture.makeBatch(status: .PARTIAL, requestId: nil)

        let count = BatchStore.shared.countPendingInventory(facet: .cycleCount)
        #expect(count == 1)
    }

    @Test func countPendingInventoryPendingBatchFacetRequiresEmptyOrNilRequestId() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .PARTIAL, requestId: "req-1")
        fixture.makeBatch(status: .PARTIAL, requestId: nil)

        let count = BatchStore.shared.countPendingInventory(facet: .pendingBatch)
        #expect(count == 1)
    }

    @Test func countPendingInventoryExcludesNonPartialAndDeleted() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .COMPLETED)
        fixture.makeBatch(status: .PARTIAL, isDeleted: true)

        let cycleCount = BatchStore.shared.countPendingInventory(facet: .cycleCount)
        let pendingBatch = BatchStore.shared.countPendingInventory(facet: .pendingBatch)
        #expect(cycleCount == 0)
        #expect(pendingBatch == 0)
    }

    // MARK: - countCompletedUnsynced

    @Test func countCompletedUnsyncedMatchesFetchCount() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeBatch(status: .COMPLETED, isSynced: false)
        fixture.makeBatch(status: .COMPLETED, isSynced: true)

        let count = BatchStore.shared.countCompletedUnsynced()
        #expect(count == 1)
    }

    // MARK: - getTransactionCount / transactionCounts

    @Test func getTransactionCountExcludesSoftDeletedStockTxns() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)
        StockTxnStore.shared.softDelete(stockTxnId: stockTxn.stock_txn_id)

        // fetchOrCreate only matches undeleted rows for (batch, drug), so this
        // creates a fresh, still-active stock txn rather than reusing the
        // soft-deleted one — leaving exactly one undeleted row for the batch.
        fixture.makeStockTxn(batch: batch)

        let count = BatchStore.shared.getTransactionCount(for: batch.batch_id)
        #expect(count == 1)
    }

    @Test func getTransactionCountReturnsZeroForBatchWithNoStockTxns() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()

        #expect(BatchStore.shared.getTransactionCount(for: batch.batch_id) == 0)
    }

    @Test func transactionCountsReturnsZeroForEveryRequestedIdWithNoStockTxns() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch1 = fixture.makeBatch()
        let batch2 = fixture.makeBatch()

        let counts = BatchStore.shared.transactionCounts(for: [batch1.batch_id, batch2.batch_id])
        #expect(counts[batch1.batch_id] == 0)
        #expect(counts[batch2.batch_id] == 0)
    }

    @Test func transactionCountsCountsStockTxnsPerBatch() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch1 = fixture.makeBatch()
        fixture.makeStockTxn(batch: batch1)
        let batch2 = fixture.makeBatch()

        let counts = BatchStore.shared.transactionCounts(for: [batch1.batch_id, batch2.batch_id])
        #expect(counts[batch1.batch_id] == 1)
        #expect(counts[batch2.batch_id] == 0)
    }

    @Test func transactionCountsReturnsEmptyForEmptyInput() {
        #expect(BatchStore.shared.transactionCounts(for: []).isEmpty)
    }

    @Test func transactionCountsInContextMatchesDefaultContextResult() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        fixture.makeStockTxn(batch: batch)

        let context = CoreDataManager.shared.context
        let viaContext = BatchStore.shared.transactionCounts(for: [batch.batch_id], in: context)
        let viaDefault = BatchStore.shared.transactionCounts(for: [batch.batch_id])
        #expect(viaContext == viaDefault)
    }

    // MARK: - updateStatus

    @Test func updateStatusPersistsNewStatusAndClearsSyncFlag() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch(status: .PARTIAL, isSynced: true)

        BatchStore.shared.updateStatus(batchId: batch.batch_id, status: .COMPLETED)

        let refetched = BatchStore.shared.fetchById(batch.batch_id)
        #expect(refetched?.status == CountStatus.COMPLETED.rawValue)
        #expect(refetched?.is_synced == false)
    }

    @Test func updateStatusToCompletedSetsEndDateTime() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch(status: .PARTIAL)
        #expect(batch.end_date_time == 0)

        BatchStore.shared.updateStatus(batchId: batch.batch_id, status: .COMPLETED)

        let refetched = BatchStore.shared.fetchById(batch.batch_id)
        #expect((refetched?.end_date_time ?? 0) > 0)
    }

    @Test func updateStatusCallsCompletionOnSuccess() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()

        var called = false
        BatchStore.shared.updateStatus(batchId: batch.batch_id, status: .COMPLETED) { called = true }
        #expect(called == true)
    }

    @Test func updateStatusSkipsCompletionForNonexistentBatch() {
        var called = false
        BatchStore.shared.updateStatus(batchId: -999_999, status: .COMPLETED) { called = true }
        #expect(called == false)
    }

    // MARK: - updateNote

    @Test func updateNotePersistsNote() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()

        BatchStore.shared.updateNote(batchId: batch.batch_id, note: "test note")

        #expect(BatchStore.shared.fetchById(batch.batch_id)?.note == "test note")
    }

    // MARK: - markSynced

    @Test func markSyncedSetsIsSyncedTrue() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch(isSynced: false)

        BatchStore.shared.markSynced(batchId: batch.batch_id)

        #expect(BatchStore.shared.fetchById(batch.batch_id)?.is_synced == true)
    }

    @Test func markSyncedInContextSetsIsSyncedTrue() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch(isSynced: false)

        let context = CoreDataManager.shared.context
        BatchStore.shared.markSynced(batchId: batch.batch_id, in: context)

        #expect(BatchStore.shared.fetchById(batch.batch_id)?.is_synced == true)
    }

    // MARK: - softDelete(ids:)

    @Test func softDeleteMarksBatchAndRelatedStockTxnsDeleted() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        BatchStore.shared.softDelete(ids: [batch.batch_id])

        #expect(BatchStore.shared.fetchById(batch.batch_id) == nil)
        #expect(StockTxnStore.shared.fetchById(stockTxn.stock_txn_id)?.is_deleted == true)
    }

    @Test func softDeleteHandlesMultipleIdsAtOnce() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch1 = fixture.makeBatch()
        let batch2 = fixture.makeBatch()

        BatchStore.shared.softDelete(ids: [batch1.batch_id, batch2.batch_id])

        #expect(BatchStore.shared.fetchById(batch1.batch_id) == nil)
        #expect(BatchStore.shared.fetchById(batch2.batch_id) == nil)
    }

    @Test func softDeleteIsSafeNoOpForNonexistentIds() {
        BatchStore.shared.softDelete(ids: [-999_999])
        // Must not crash; nothing to assert beyond survival.
    }
}
