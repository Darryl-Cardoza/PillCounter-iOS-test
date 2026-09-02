//
//  TransactionStoreTests.swift
//  PillCounterTests
//
//  Bottle-tracking methods on TransactionStore. Runs against the real on-disk
//  CoreData store via CoreDataManager.shared (see SQLiteCoreDataStack.swift for
//  why); every fixture is uniquely-id'd and torn down at the end of each test.
//

import CoreData
import Foundation
import Testing
@testable import PillCounter

@Suite(.serialized)
struct TransactionStoreTests {

    @Test func newTransactionHasEmptyBottleList() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        #expect(TransactionStore.shared.getBottleList(txnId: txn.txn_id) == [])
    }

    @Test func setBottleListPersistsAndRoundTrips() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let bottles = [
            BottleInfo(lotNumber: "L1", expirationDate: "01-01-2027", serialNumber: "S1", txnDetailsIds: [], scannedAt: 1)
        ]
        TransactionStore.shared.setBottleList(txnId: txn.txn_id, bottles)

        #expect(TransactionStore.shared.getBottleList(txnId: txn.txn_id) == bottles)
    }

    @Test func appendBottleAddsWithoutClobberingExisting() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let first = BottleInfo(lotNumber: "L1", expirationDate: nil, serialNumber: nil, txnDetailsIds: [1], scannedAt: 1)
        let second = BottleInfo(lotNumber: "L2", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 2)

        TransactionStore.shared.setBottleList(txnId: txn.txn_id, [first])
        TransactionStore.shared.appendBottle(txnId: txn.txn_id, second)

        let result = TransactionStore.shared.getBottleList(txnId: txn.txn_id)
        #expect(result == [first, second])
    }

    @Test func replaceLastBottleOverwritesOnlyLastEntry() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let first = BottleInfo(lotNumber: "L1", expirationDate: nil, serialNumber: nil, txnDetailsIds: [1], scannedAt: 1)
        let second = BottleInfo(lotNumber: "L2", expirationDate: nil, serialNumber: nil, txnDetailsIds: [2], scannedAt: 2)
        let replacement = BottleInfo(lotNumber: "L3", expirationDate: "05-05-2028", serialNumber: "SNEW", txnDetailsIds: [], scannedAt: 3)

        TransactionStore.shared.setBottleList(txnId: txn.txn_id, [first, second])
        TransactionStore.shared.replaceLastBottle(txnId: txn.txn_id, replacement)

        let result = TransactionStore.shared.getBottleList(txnId: txn.txn_id)
        #expect(result.count == 2)
        #expect(result.first == first)
        #expect(result.last == replacement)
    }

    @Test func replaceLastBottleNoOpsOnEmptyList() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let replacement = BottleInfo(lotNumber: "L1", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        TransactionStore.shared.replaceLastBottle(txnId: txn.txn_id, replacement)

        #expect(TransactionStore.shared.getBottleList(txnId: txn.txn_id) == [])
    }

    @Test func allFourMethodsAreSafeNoOpsForNonexistentTxnId() {
        let bogusTxnId: Int64 = -999_999

        #expect(TransactionStore.shared.getBottleList(txnId: bogusTxnId) == [])

        // These must not crash even though there's no row to update. Note:
        // appendBottle/replaceLastBottle return the locally-mutated array
        // (built from getBottleList, which is [] for a bogus id) regardless
        // of whether the underlying write actually persisted anything — the
        // meaningful assertion is that nothing was actually written to the
        // (nonexistent) row, verified via a fresh getBottleList read below.
        TransactionStore.shared.setBottleList(txnId: bogusTxnId, [
            BottleInfo(lotNumber: "L", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        ])
        TransactionStore.shared.appendBottle(
            txnId: bogusTxnId,
            BottleInfo(lotNumber: "L2", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 2)
        )
        TransactionStore.shared.replaceLastBottle(
            txnId: bogusTxnId,
            BottleInfo(lotNumber: "L3", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 3)
        )

        // Confirm nothing was actually persisted under this id.
        #expect(TransactionStore.shared.getBottleList(txnId: bogusTxnId) == [])
    }

    // MARK: - fetchById(_:in:)

    @Test func fetchByIdInContextReturnsMatchingRow() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let context = CoreDataManager.shared.context
        let result = TransactionStore.shared.fetchById(txn.txn_id, in: context)
        #expect(result?.txn_id == txn.txn_id)
    }

    @Test func fetchByIdInContextReturnsNilForMissingRow() {
        let context = CoreDataManager.shared.context
        #expect(TransactionStore.shared.fetchById(-999_999, in: context) == nil)
    }

    // MARK: - fetchPartial / fetchPartialPage

    @Test func fetchPartialExcludesCompletedAndBatched() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let pending = fixture.makeTransaction(isDispense: true)
        let batched = fixture.makeTransaction(isDispense: true, batchId: 555)
        let completed = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: completed.txn_id, status: .COMPLETED)

        let results = TransactionStore.shared.fetchPartial(for: fixture.user, isDispense: true)
        let ids = Set(results.map { $0.txn_id })
        #expect(ids.contains(pending.txn_id))
        #expect(!ids.contains(batched.txn_id))
        #expect(!ids.contains(completed.txn_id))
    }

    @Test func fetchPartialFiltersByIsDispense() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let dispense = fixture.makeTransaction(isDispense: true)
        let stock = fixture.makeTransaction(isDispense: false)

        let dispenseResults = TransactionStore.shared.fetchPartial(for: fixture.user, isDispense: true)
        let stockResults = TransactionStore.shared.fetchPartial(for: fixture.user, isDispense: false)

        #expect(dispenseResults.map { $0.txn_id }.contains(dispense.txn_id))
        #expect(!dispenseResults.map { $0.txn_id }.contains(stock.txn_id))
        #expect(stockResults.map { $0.txn_id }.contains(stock.txn_id))
        #expect(!stockResults.map { $0.txn_id }.contains(dispense.txn_id))
    }

    @Test func fetchPartialInContextMatchesDefaultContextResult() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeTransaction(isDispense: true)

        let context = CoreDataManager.shared.context
        guard let userInContext = UserStore.shared.fetchByUserId(fixture.userId, in: context) else {
            Issue.record("user not found in explicit context")
            return
        }
        let viaContext = TransactionStore.shared.fetchPartial(for: userInContext, isDispense: true, in: context)
        let viaDefault = TransactionStore.shared.fetchPartial(for: fixture.user, isDispense: true)
        #expect(Set(viaContext.map { $0.txn_id }) == Set(viaDefault.map { $0.txn_id }))
    }

    @Test func fetchPartialPageRespectsLimitAndOffset() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        for _ in 0..<5 { fixture.makeTransaction(isDispense: true) }

        let page1 = TransactionStore.shared.fetchPartialPage(for: fixture.user, isDispense: true, limit: 2, offset: 0)
        let page2 = TransactionStore.shared.fetchPartialPage(for: fixture.user, isDispense: true, limit: 2, offset: 2)
        let page3 = TransactionStore.shared.fetchPartialPage(for: fixture.user, isDispense: true, limit: 2, offset: 4)

        #expect(page1.count == 2)
        #expect(page2.count == 2)
        #expect(page3.count == 1)
        let allIds = Set(page1.map { $0.txn_id } + page2.map { $0.txn_id } + page3.map { $0.txn_id })
        #expect(allIds.count == 5)
    }

    @Test func fetchPartialPageBeyondEndReturnsEmpty() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeTransaction(isDispense: true)

        let unpaged = TransactionStore.shared.fetchPartial(for: fixture.user, isDispense: true)
        #expect(unpaged.count == 1, "expected exactly 1 unpaged row for this fresh fixture, got \(unpaged.count): \(unpaged.map { $0.txn_id })")

        let results = TransactionStore.shared.fetchPartialPage(for: fixture.user, isDispense: true, limit: 10, offset: 100)
        #expect(results.isEmpty, "expected empty page at offset 100 with only \(unpaged.count) row(s) total, got \(results.map { $0.txn_id })")
    }

    // MARK: - fetchByTimeRange / fetchByTimeRangePage

    @Test func fetchByTimeRangeReturnsOnlyRowsInsideBounds() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let now = txn.created_at

        let inRange = TransactionStore.shared.fetchByTimeRange(for: fixture.user, startTime: now - 1000, endTime: now + 1000)
        let beforeRange = TransactionStore.shared.fetchByTimeRange(for: fixture.user, startTime: now + 1000, endTime: now + 2000)
        let afterRange = TransactionStore.shared.fetchByTimeRange(for: fixture.user, startTime: now - 2000, endTime: now - 1000)

        #expect(inRange.map { $0.txn_id }.contains(txn.txn_id))
        #expect(!beforeRange.map { $0.txn_id }.contains(txn.txn_id))
        #expect(!afterRange.map { $0.txn_id }.contains(txn.txn_id))
    }

    @Test func fetchByTimeRangeBoundsAreInclusive() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let now = txn.created_at

        let exactBounds = TransactionStore.shared.fetchByTimeRange(for: fixture.user, startTime: now, endTime: now)
        #expect(exactBounds.map { $0.txn_id }.contains(txn.txn_id))
    }

    @Test func fetchByTimeRangeExcludesSoftDeleted() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let now = txn.created_at
        TransactionStore.shared.softDelete(txnId: txn.txn_id)

        let results = TransactionStore.shared.fetchByTimeRange(for: fixture.user, startTime: now - 1000, endTime: now + 1000)
        #expect(!results.map { $0.txn_id }.contains(txn.txn_id))
    }

    @Test func fetchByTimeRangeInContextMatchesDefaultContextResult() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let now = txn.created_at

        let context = CoreDataManager.shared.context
        guard let userInContext = UserStore.shared.fetchByUserId(fixture.userId, in: context) else {
            Issue.record("user not found in explicit context")
            return
        }
        let viaContext = TransactionStore.shared.fetchByTimeRange(for: userInContext, startTime: now - 1000, endTime: now + 1000, in: context)
        let viaDefault = TransactionStore.shared.fetchByTimeRange(for: fixture.user, startTime: now - 1000, endTime: now + 1000)
        #expect(Set(viaContext.map { $0.txn_id }) == Set(viaDefault.map { $0.txn_id }))
    }

    @Test func fetchByTimeRangePageRespectsLimitAndOffset() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        var txns: [PillCountTransactionEntity] = []
        for _ in 0..<4 { txns.append(fixture.makeTransaction()) }
        let start = txns.map { $0.created_at }.min()! - 1000
        let end = txns.map { $0.created_at }.max()! + 1000

        let page1 = TransactionStore.shared.fetchByTimeRangePage(for: fixture.user, startTime: start, endTime: end, limit: 2, offset: 0)
        let page2 = TransactionStore.shared.fetchByTimeRangePage(for: fixture.user, startTime: start, endTime: end, limit: 2, offset: 2)

        #expect(page1.count == 2)
        #expect(page2.count == 2)
        #expect(Set(page1.map { $0.txn_id }).isDisjoint(with: Set(page2.map { $0.txn_id })))
    }

    // MARK: - fetchCompletedUnsyncedPage

    @Test func fetchCompletedUnsyncedPageOnlyReturnsCompletedUnsyncedDispense() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let matching = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: matching.txn_id, status: .COMPLETED)

        let syncedAlready = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: syncedAlready.txn_id, status: .COMPLETED)
        TransactionStore.shared.updateSynced(txnId: syncedAlready.txn_id)

        let stillPartial = fixture.makeTransaction(isDispense: true)

        let stockNotDispense = fixture.makeTransaction(isDispense: false)
        TransactionStore.shared.updateStatus(txnId: stockNotDispense.txn_id, status: .COMPLETED)

        sharedCoreDataLock.lock()
        let previousUserId = AppStorageManager.shared.userId
        AppStorageManager.shared.userId = fixture.userId
        defer {
            AppStorageManager.shared.userId = previousUserId
            sharedCoreDataLock.unlock()
        }

        let results = TransactionStore.shared.fetchCompletedUnsyncedPage(limit: 50, offset: 0)
        let ids = Set(results.map { $0.txn_id })
        #expect(ids.contains(matching.txn_id))
        #expect(!ids.contains(syncedAlready.txn_id))
        #expect(!ids.contains(stillPartial.txn_id))
        #expect(!ids.contains(stockNotDispense.txn_id))
    }

    @Test func fetchCompletedUnsyncedPageReturnsEmptyWhenNoUserLoggedIn() {
        sharedCoreDataLock.lock()
        let previousUserId = AppStorageManager.shared.userId
        AppStorageManager.shared.userId = nil
        defer {
            AppStorageManager.shared.userId = previousUserId
            sharedCoreDataLock.unlock()
        }

        #expect(TransactionStore.shared.fetchCompletedUnsyncedPage(limit: 10, offset: 0).isEmpty)
    }

    // MARK: - fetchAllPage

    @Test func fetchAllPageRespectsLimitAndOffsetNewestFirst() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let first = fixture.makeTransaction()
        let second = fixture.makeTransaction()
        let third = fixture.makeTransaction()

        let page1 = TransactionStore.shared.fetchAllPage(for: fixture.user, limit: 2, offset: 0)
        #expect(page1.count == 2)
        #expect(page1.map { $0.txn_id } == [third.txn_id, second.txn_id])

        let page2 = TransactionStore.shared.fetchAllPage(for: fixture.user, limit: 2, offset: 2)
        #expect(page2.map { $0.txn_id } == [first.txn_id])
    }

    @Test func fetchAllPageExcludesSoftDeleted() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let kept = fixture.makeTransaction()
        let deleted = fixture.makeTransaction()
        TransactionStore.shared.softDelete(txnId: deleted.txn_id)

        let results = TransactionStore.shared.fetchAllPage(for: fixture.user, limit: 50, offset: 0)
        let ids = Set(results.map { $0.txn_id })
        #expect(ids.contains(kept.txn_id))
        #expect(!ids.contains(deleted.txn_id))
    }

    // MARK: - countByTimeRange

    @Test func countByTimeRangeMatchesFetchByTimeRangeCount() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        for _ in 0..<3 { fixture.makeTransaction(isDispense: true) }
        let txns = fixture.txnIds.compactMap { TransactionStore.shared.fetchById($0) }
        let start = txns.map { $0.created_at }.min()! - 1000
        let end = txns.map { $0.created_at }.max()! + 1000

        let count = TransactionStore.shared.countByTimeRange(for: fixture.user, startTime: start, endTime: end, status: nil)
        #expect(count == 3)
    }

    @Test func countByTimeRangeFiltersByStatusWhenGiven() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let completed = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: completed.txn_id, status: .COMPLETED)
        let partial = fixture.makeTransaction(isDispense: true)
        let start = min(completed.created_at, partial.created_at) - 1000
        let end = max(completed.created_at, partial.created_at) + 1000

        let completedCount = TransactionStore.shared.countByTimeRange(for: fixture.user, startTime: start, endTime: end, status: .COMPLETED)
        let partialCount = TransactionStore.shared.countByTimeRange(for: fixture.user, startTime: start, endTime: end, status: .PARTIAL)
        #expect(completedCount == 1)
        #expect(partialCount == 1)
    }

    @Test func countByTimeRangeExcludesNonDispense() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let stock = fixture.makeTransaction(isDispense: false)
        let start = stock.created_at - 1000
        let end = stock.created_at + 1000

        let count = TransactionStore.shared.countByTimeRange(for: fixture.user, startTime: start, endTime: end, status: nil)
        #expect(count == 0)
    }

    // MARK: - countPendingDispense

    @Test func countPendingDispenseAllCountsAllPendingRegardlessOfFacet() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeTransaction(isDispense: true)
        fixture.makeTransaction(isDispense: true)

        let count = TransactionStore.shared.countPendingDispense(for: fixture.user, facet: .all)
        #expect(count == 2)
    }

    @Test func countPendingDispenseExcludesOnHoldAndCompletedAndBatched() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let pending = fixture.makeTransaction(isDispense: true)
        let onHold = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: onHold.txn_id, status: .ON_HOLD)
        let completed = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: completed.txn_id, status: .COMPLETED)
        fixture.makeTransaction(isDispense: true, batchId: 42)

        let count = TransactionStore.shared.countPendingDispense(for: fixture.user, facet: .all)
        #expect(count == 1)
        _ = pending
    }

    @Test func countPendingDispenseHighPriorityFacetIsCaseInsensitive() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        fixture.makeTransaction(isDispense: true, priority: "High")
        fixture.makeTransaction(isDispense: true, priority: "low")

        let count = TransactionStore.shared.countPendingDispense(for: fixture.user, facet: .highPriority)
        #expect(count == 1)
    }

    @Test func countPendingDispenseHazardousFacetMatchesDrugFlag() {
        let hazardousFixture = BottleTrackingFixture(isHazardous: true)
        defer { hazardousFixture.cleanUp() }
        hazardousFixture.makeTransaction(isDispense: true)

        let count = TransactionStore.shared.countPendingDispense(for: hazardousFixture.user, facet: .hazardous)
        #expect(count == 1)
    }

    @Test func countPendingDispenseHazardousFacetExcludesNonHazardousDrug() {
        let fixture = BottleTrackingFixture(isHazardous: false)
        defer { fixture.cleanUp() }
        fixture.makeTransaction(isDispense: true)

        let count = TransactionStore.shared.countPendingDispense(for: fixture.user, facet: .hazardous)
        #expect(count == 0)
    }

    @Test func countPendingDispenseControlledFacetRequiresNonEmptyDrugType() {
        let controlledFixture = BottleTrackingFixture(drugType: "CII")
        defer { controlledFixture.cleanUp() }
        controlledFixture.makeTransaction(isDispense: true)

        let count = TransactionStore.shared.countPendingDispense(for: controlledFixture.user, facet: .controlled)
        #expect(count == 1)
    }

    // MARK: - countCompletedUnsynced

    @Test func countCompletedUnsyncedMatchesFetchCompletedUnsyncedCount() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let matching = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: matching.txn_id, status: .COMPLETED)
        let partial = fixture.makeTransaction(isDispense: true)

        sharedCoreDataLock.lock()
        let previousUserId = AppStorageManager.shared.userId
        AppStorageManager.shared.userId = fixture.userId
        defer {
            AppStorageManager.shared.userId = previousUserId
            sharedCoreDataLock.unlock()
        }

        let count = TransactionStore.shared.countCompletedUnsynced()
        #expect(count == 1)
        _ = partial
    }

    @Test func countCompletedUnsyncedReturnsZeroWhenNoUserLoggedIn() {
        sharedCoreDataLock.lock()
        let previousUserId = AppStorageManager.shared.userId
        AppStorageManager.shared.userId = nil
        defer {
            AppStorageManager.shared.userId = previousUserId
            sharedCoreDataLock.unlock()
        }

        #expect(TransactionStore.shared.countCompletedUnsynced() == 0)
    }

    // MARK: - getBottleList(_:in:)

    @Test func getBottleListInContextMatchesDefaultContextResult() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let bottle = BottleInfo(lotNumber: "LX", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 9)
        TransactionStore.shared.setBottleList(txnId: txn.txn_id, [bottle])

        let context = CoreDataManager.shared.context
        let result = TransactionStore.shared.getBottleList(txnId: txn.txn_id, in: context)
        #expect(result == [bottle])
    }

    // MARK: - updateSynced(_:in:)

    @Test func updateSyncedInContextSetsIsSyncedTrue() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction(isDispense: false)

        let context = CoreDataManager.shared.context
        TransactionStore.shared.updateSynced(txnId: txn.txn_id, in: context)

        let refetched = TransactionStore.shared.fetchById(txn.txn_id)
        #expect(refetched?.is_synced == true)
    }

    // MARK: - expectedImageFilenames

    @Test func expectedImageFilenamesCombinesBottleAndDetailImages() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        TransactionStore.shared.setBottleList(txnId: txn.txn_id, [
            BottleInfo(lotNumber: "L1", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1, barcodeImagePath: "bottle1.jpg")
        ])
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 5, imagePath: "detail1.jpg")

        let filenames = Set(TransactionStore.shared.expectedImageFilenames(txnId: txn.txn_id))
        #expect(filenames == ["bottle1.jpg", "detail1.jpg"])
    }

    @Test func expectedImageFilenamesFiltersOutEmptyPaths() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 5, imagePath: "")

        #expect(TransactionStore.shared.expectedImageFilenames(txnId: txn.txn_id).isEmpty)
    }

    @Test func expectedImageFilenamesInContextMatchesDefaultContextResult() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 5, imagePath: "detail-x.jpg")

        let context = CoreDataManager.shared.context
        let viaContext = Set(TransactionStore.shared.expectedImageFilenames(txnId: txn.txn_id, in: context))
        let viaDefault = Set(TransactionStore.shared.expectedImageFilenames(txnId: txn.txn_id))
        #expect(viaContext == viaDefault)
    }

    // MARK: - attemptHardDeleteIfEligible

    @Test func attemptHardDeleteIfEligibleDeletesWhenAllConditionsMet() {
        let fixture = BottleTrackingFixture()
        let txn = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: txn.txn_id, status: .COMPLETED)

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = false
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        // No expected images ⇒ ImageDeliveryTracker.allDelivered([]) is vacuously true.
        TransactionStore.shared.updateSynced(txnId: txn.txn_id)

        #expect(TransactionStore.shared.fetchById(txn.txn_id) == nil)
        fixture.cleanUp() // no-ops for the already hard-deleted txn; still clears the user row.
    }

    @Test func attemptHardDeleteIfEligibleKeepsRowWhenLocalStorageAllowed() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: txn.txn_id, status: .COMPLETED)

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = true
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        #expect(TransactionStore.shared.attemptHardDeleteIfEligible(txnId: txn.txn_id) == false)
        #expect(TransactionStore.shared.fetchById(txn.txn_id) != nil)
    }

    @Test func attemptHardDeleteIfEligibleKeepsRowWhenNotSynced() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: txn.txn_id, status: .COMPLETED)

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = false
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        #expect(TransactionStore.shared.attemptHardDeleteIfEligible(txnId: txn.txn_id) == false)
        #expect(TransactionStore.shared.fetchById(txn.txn_id) != nil)
    }

    @Test func attemptHardDeleteIfEligibleKeepsRowWhenNotDispense() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction(isDispense: false)
        TransactionStore.shared.updateStatus(txnId: txn.txn_id, status: .COMPLETED)

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = false
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        TransactionStore.shared.updateSynced(txnId: txn.txn_id)
        #expect(TransactionStore.shared.fetchById(txn.txn_id) != nil)
    }

    @Test func attemptHardDeleteIfEligibleKeepsRowWhenStillPartial() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction(isDispense: true)

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = false
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        #expect(TransactionStore.shared.attemptHardDeleteIfEligible(txnId: txn.txn_id) == false)
        #expect(TransactionStore.shared.fetchById(txn.txn_id) != nil)
    }

    @Test func attemptHardDeleteIfEligibleReturnsFalseForNonexistentTxn() {
        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = false
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        #expect(TransactionStore.shared.attemptHardDeleteIfEligible(txnId: -999_999) == false)
    }

    @Test func attemptHardDeleteIfEligibleInContextDeletesWhenAllConditionsMet() {
        let fixture = BottleTrackingFixture()
        let txn = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: txn.txn_id, status: .FORCE_COMPLETED)

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = false
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        let context = CoreDataManager.shared.context
        TransactionStore.shared.updateSynced(txnId: txn.txn_id, in: context)

        #expect(TransactionStore.shared.fetchById(txn.txn_id) == nil)
        fixture.cleanUp()
    }

    // MARK: - hardDelete(_:in:)

    @Test func hardDeleteInContextRemovesRowAndCascadesDetails() {
        let fixture = BottleTrackingFixture()
        let txn = fixture.makeTransaction()
        let detail = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 10)!

        let context = CoreDataManager.shared.context
        TransactionStore.shared.hardDelete(txnId: txn.txn_id, in: context)

        #expect(TransactionStore.shared.fetchById(txn.txn_id) == nil)
        #expect(TransactionDetailStore.shared.fetchById(detail.txn_details_id) == nil)
        fixture.cleanUp() // no-op for the already-deleted txn; harmless.
    }

    // MARK: - sweepStaleSyncedTransactions

    @Test func sweepStaleSyncedTransactionsDeletesOnlyStaleCompletedSynced() {
        let fixture = BottleTrackingFixture()
        let stale = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: stale.txn_id, status: .COMPLETED)

        let context = CoreDataManager.shared.context
        context.performAndWait {
            if let entity = TransactionStore.shared.fetchById(stale.txn_id, in: context) {
                entity.is_synced = true
                entity.updated_at = Int64(Date().timeIntervalSince1970 * 1000) - 1_000_000
                CoreDataManager.shared.save(context: context)
            }
        }

        let fresh = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: fresh.txn_id, status: .COMPLETED)
        TransactionStore.shared.updateSynced(txnId: fresh.txn_id)

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = false
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        TransactionStore.shared.sweepStaleSyncedTransactions(olderThan: 60)

        #expect(TransactionStore.shared.fetchById(stale.txn_id) == nil)
        fixture.cleanUp() // clears whichever of the two txns is still present, plus the user row.
    }

    @Test func sweepStaleSyncedTransactionsNoOpsWhenLocalStorageAllowed() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: txn.txn_id, status: .COMPLETED)

        let context = CoreDataManager.shared.context
        context.performAndWait {
            if let entity = TransactionStore.shared.fetchById(txn.txn_id, in: context) {
                entity.is_synced = true
                entity.updated_at = 0
                CoreDataManager.shared.save(context: context)
            }
        }

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        AppStorageManager.shared.allowLocalStorage = true
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        TransactionStore.shared.sweepStaleSyncedTransactions(olderThan: 60)
        #expect(TransactionStore.shared.fetchById(txn.txn_id) != nil)
    }

    @Test func sweepStaleSyncedTransactionsKeepsRecentRows() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction(isDispense: true)
        TransactionStore.shared.updateStatus(txnId: txn.txn_id, status: .COMPLETED)

        let previousAllowLocal = AppStorageManager.shared.allowLocalStorage
        // allowLocalStorage true during the sync write so updateSynced's own
        // attemptHardDeleteIfEligible does not delete the row before the sweep
        // even gets to run — this test is specifically about the sweep's own
        // recency check, not the eligible-delete path (covered separately above).
        AppStorageManager.shared.allowLocalStorage = true
        TransactionStore.shared.updateSynced(txnId: txn.txn_id)
        #expect(TransactionStore.shared.fetchById(txn.txn_id) != nil)

        AppStorageManager.shared.allowLocalStorage = false
        defer { AppStorageManager.shared.allowLocalStorage = previousAllowLocal }

        TransactionStore.shared.sweepStaleSyncedTransactions(olderThan: 3600)
        #expect(TransactionStore.shared.fetchById(txn.txn_id) != nil)
    }
}
