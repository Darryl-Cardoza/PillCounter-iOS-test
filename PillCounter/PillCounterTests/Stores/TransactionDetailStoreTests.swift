//
//  TransactionDetailStoreTests.swift
//  PillCounterTests
//
//  Tests for TransactionDetailStore.sumPillCount(detailIds:). Runs against the
//  real on-disk CoreData store (see SQLiteCoreDataStack.swift for why); every
//  fixture is uniquely-id'd and torn down at the end of each test.
//

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
}
