//
//  TransactionDetailStoreTests.swift
//  PillCounterTests
//
//  Tests for TransactionDetailStore.sumPillCount(detailIds:). Runs against the
//  real on-disk CoreData store (see SQLiteCoreDataStack.swift for why); every
//  fixture is uniquely-id'd and torn down at the end of each test.
//

import CoreData
import Testing
@testable import PillCounter

@Suite(.serialized)
struct TransactionDetailStoreTests {

    @Test func sumsPillCountAcrossGivenIds() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let d1 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 10)!
        let d2 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 15)!

        let sum = TransactionDetailStore.shared.sumPillCount(detailIds: [d1.txn_details_id, d2.txn_details_id])
        #expect(sum == 25)
    }

    @Test func excludesSoftDeletedRows() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let d1 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 10)!
        let d2 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 15)!
        TransactionDetailStore.shared.softDelete(detailId: d2.txn_details_id)

        let sum = TransactionDetailStore.shared.sumPillCount(detailIds: [d1.txn_details_id, d2.txn_details_id])
        #expect(sum == 10)
    }

    @Test func emptyIdsReturnsZero() {
        #expect(TransactionDetailStore.shared.sumPillCount(detailIds: []) == 0)
    }

    @Test func nonexistentIdsReturnZero() {
        #expect(TransactionDetailStore.shared.sumPillCount(detailIds: [-1, -2, -3]) == 0)
    }

    @Test func subsetSumIsCorrect() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let d1 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 5)!
        let d2 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 7)!
        let d3 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 100)!

        // Only sum a subset (d1, d2) — d3's count must not be included.
        let sum = TransactionDetailStore.shared.sumPillCount(detailIds: [d1.txn_details_id, d2.txn_details_id])
        #expect(sum == 12)
        _ = d3
    }

    @Test func sumPillCountInContextMatchesDefaultContextResult() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let d1 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 8)!

        let context = CoreDataManager.shared.context
        let viaContext = TransactionDetailStore.shared.sumPillCount(detailIds: [d1.txn_details_id], in: context)
        let viaDefault = TransactionDetailStore.shared.sumPillCount(detailIds: [d1.txn_details_id])
        #expect(viaContext == viaDefault)
        #expect(viaContext == 8)
    }

    @Test func sumPillCountInContextReturnsZeroForEmptyIds() {
        let context = CoreDataManager.shared.context
        #expect(TransactionDetailStore.shared.sumPillCount(detailIds: [], in: context) == 0)
    }

    // MARK: - fetchAll(txnId:in:)

    @Test func fetchAllInContextMatchesDefaultContextResult() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 3)
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 4)

        let context = CoreDataManager.shared.context
        let viaContext = TransactionDetailStore.shared.fetchAll(txnId: txn.txn_id, in: context)
        let viaDefault = TransactionDetailStore.shared.fetchAll(txnId: txn.txn_id)
        #expect(viaContext.count == 2)
        #expect(Set(viaContext.map { $0.txn_details_id }) == Set(viaDefault.map { $0.txn_details_id }))
    }

    @Test func fetchAllInContextExcludesSoftDeleted() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let kept = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 3)!
        let deleted = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 4)!
        TransactionDetailStore.shared.softDelete(detailId: deleted.txn_details_id)

        let context = CoreDataManager.shared.context
        let results = TransactionDetailStore.shared.fetchAll(txnId: txn.txn_id, in: context)
        let ids = Set(results.map { $0.txn_details_id })
        #expect(ids.contains(kept.txn_details_id))
        #expect(!ids.contains(deleted.txn_details_id))
    }

    @Test func fetchAllInContextReturnsEmptyForUnknownTxn() {
        let context = CoreDataManager.shared.context
        #expect(TransactionDetailStore.shared.fetchAll(txnId: -999_999, in: context).isEmpty)
    }

    // MARK: - totalCountsForSteps

    @Test func totalCountsForStepsSumsPillCountPerTransactionForGivenStep() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn1 = fixture.makeTransaction()
        let txn2 = fixture.makeTransaction()

        TransactionDetailStore.shared.add(txnId: txn1.txn_id, pillCount: 5, type: ControlledStep.containerInitiate.rawValue)
        TransactionDetailStore.shared.add(txnId: txn1.txn_id, pillCount: 3, type: ControlledStep.containerInitiate.rawValue)
        TransactionDetailStore.shared.add(txnId: txn2.txn_id, pillCount: 10, type: ControlledStep.containerInitiate.rawValue)
        TransactionDetailStore.shared.add(txnId: txn1.txn_id, pillCount: 99, type: ControlledStep.vial.rawValue) // different step, must not count.

        let totals = TransactionDetailStore.shared.totalCountsForSteps(txnIds: [txn1.txn_id, txn2.txn_id], step: .containerInitiate)
        #expect(totals[txn1.txn_id] == 8)
        #expect(totals[txn2.txn_id] == 10)
    }

    @Test func totalCountsForStepsReturnsZeroForTransactionsWithNoMatchingDetails() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let totals = TransactionDetailStore.shared.totalCountsForSteps(txnIds: [txn.txn_id], step: .containerInitiate)
        #expect(totals[txn.txn_id] == 0)
    }

    @Test func totalCountsForStepsExcludesSoftDeletedDetails() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let kept = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 5, type: ControlledStep.containerInitiate.rawValue)!
        let deleted = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 20, type: ControlledStep.containerInitiate.rawValue)!
        TransactionDetailStore.shared.softDelete(detailId: deleted.txn_details_id)

        let totals = TransactionDetailStore.shared.totalCountsForSteps(txnIds: [txn.txn_id], step: .containerInitiate)
        #expect(totals[txn.txn_id] == 5)
        _ = kept
    }

    @Test func totalCountsForStepsReturnsEmptyForEmptyInput() {
        #expect(TransactionDetailStore.shared.totalCountsForSteps(txnIds: [], step: .containerInitiate).isEmpty)
    }

    @Test func totalCountsForStepsInContextMatchesDefaultContextResult() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 6, type: ControlledStep.scan.rawValue)

        let context = CoreDataManager.shared.context
        let viaContext = TransactionDetailStore.shared.totalCountsForSteps(txnIds: [txn.txn_id], step: .scan, in: context)
        let viaDefault = TransactionDetailStore.shared.totalCountsForSteps(txnIds: [txn.txn_id], step: .scan)
        #expect(viaContext == viaDefault)
        #expect(viaContext[txn.txn_id] == 6)
    }

    // MARK: - hardDeleteAll(txnId:)

    @Test func hardDeleteAllRemovesEveryDetailRowForTxn() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        let kept = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 5)!
        let deleted = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 3)!
        TransactionDetailStore.shared.softDelete(detailId: deleted.txn_details_id)

        TransactionDetailStore.shared.hardDeleteAll(txnId: txn.txn_id)

        #expect(TransactionDetailStore.shared.fetchById(kept.txn_details_id) == nil)
        #expect(TransactionDetailStore.shared.fetchById(deleted.txn_details_id) == nil)
        #expect(TransactionDetailStore.shared.fetchAll(txnId: txn.txn_id).isEmpty)
    }

    @Test func hardDeleteAllReturnsImagePathsOfDeletedRows() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 1, imagePath: "img1.enc")
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 2, imagePath: "img2.enc")
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 3)

        let result = TransactionDetailStore.shared.hardDeleteAll(txnId: txn.txn_id)
        #expect(result.success == true)
        #expect(Set(result.imagePaths) == Set(["img1.enc", "img2.enc"]))
    }

    @Test func hardDeleteAllDoesNotTouchOtherTransactions() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn1 = fixture.makeTransaction()
        let txn2 = fixture.makeTransaction()
        TransactionDetailStore.shared.add(txnId: txn1.txn_id, pillCount: 5)
        let untouched = TransactionDetailStore.shared.add(txnId: txn2.txn_id, pillCount: 7)!

        TransactionDetailStore.shared.hardDeleteAll(txnId: txn1.txn_id)

        #expect(TransactionDetailStore.shared.fetchAll(txnId: txn1.txn_id).isEmpty)
        #expect(TransactionDetailStore.shared.fetchById(untouched.txn_details_id) != nil)
    }

    @Test func hardDeleteAllReturnsEmptyForUnknownTxn() {
        let result = TransactionDetailStore.shared.hardDeleteAll(txnId: -999_999)
        #expect(result.success == true)
        #expect(result.imagePaths.isEmpty)
    }
}
