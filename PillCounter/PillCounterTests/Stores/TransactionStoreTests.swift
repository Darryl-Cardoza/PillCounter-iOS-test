//
//  TransactionStoreTests.swift
//  PillCounterTests
//
//  Bottle-tracking methods on TransactionStore. Runs against the real on-disk
//  CoreData store via CoreDataManager.shared (see SQLiteCoreDataStack.swift for
//  why); every fixture is uniquely-id'd and torn down at the end of each test.
//

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
}
