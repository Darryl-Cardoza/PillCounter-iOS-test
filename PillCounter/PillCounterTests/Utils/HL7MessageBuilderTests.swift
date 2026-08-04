//
//  HL7MessageBuilderTests.swift
//  PillCounterTests
//
//  buildZSN() is a private helper on HL7CompletionBuilder, so it can't be
//  called directly (private is not upgraded by @testable). These tests drive
//  it indirectly through buildCompletionMessage() and parse the resulting raw
//  HL7 message for ZSN segments — exercising the exact same code path used in
//  production. Runs against the real on-disk CoreData store (see
//  SQLiteCoreDataStack.swift for why); fixtures are uniquely-id'd and torn
//  down at the end of each test.
//

import Testing
@testable import PillCounter

@Suite(.serialized)
struct HL7MessageBuilderTests {

    /// Splits a raw HL7 message into its ZSN segments, each represented as its
    /// pipe-delimited fields (field 0 is the segment name "ZSN").
    private func zsnSegments(in message: String) -> [[String]] {
        message
            .components(separatedBy: "\r")
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { $0.hasPrefix("ZSN") }
            .map { $0.components(separatedBy: "|") }
    }

    @Test func emptyBottleListFallsBackToLegacyPerDetailRows() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 10)
        TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 20)

        // No bottle list set — expect legacy fallback: one ZSN row per detail.
        let refreshedTxn = TransactionStore.shared.fetchById(txn.txn_id)!
        let message = HL7CompletionBuilder().buildCompletionMessage(txn: refreshedTxn, user: fixture.user)
        let rows = zsnSegments(in: message)

        #expect(rows.count == 2)
        // ZSN-3 is quantityFromThisStockItem in this builder's field ordering
        // (setId, ndc, quantity, ...); no lot/exp/serial for legacy rows.
        let quantities = Set(rows.map { $0[2] })
        #expect(quantities == Set(["10", "20"]))
    }

    @Test func singleBottleOwningAllDetailsProducesOneRowWithFullSum() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let d1 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 10)!
        let d2 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 15)!

        let bottle = BottleInfo(
            lotNumber: "LOT1", expirationDate: "01-01-2027", serialNumber: "SN1",
            txnDetailsIds: [d1.txn_details_id, d2.txn_details_id], scannedAt: 1
        )
        TransactionStore.shared.setBottleList(txnId: txn.txn_id, [bottle])

        let refreshedTxn = TransactionStore.shared.fetchById(txn.txn_id)!
        let message = HL7CompletionBuilder().buildCompletionMessage(txn: refreshedTxn, user: fixture.user)
        let rows = zsnSegments(in: message)

        #expect(rows.count == 1)
        #expect(rows[0][2] == "25")
        #expect(rows[0][6] == "LOT1")
        #expect(rows[0][7] == "01-01-2027")
        #expect(rows[0][8] == "SN1")
    }

    @Test func twoBottlesWhereOneBottlesDetailWasDeletedExcludesItFromSum() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let d1 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 10)!
        let d2 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 15)!
        let d3 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 30)!

        // d2 belongs to bottle #1 but gets soft-deleted afterwards — must drop
        // out of bottle #1's live sum without needing any snapshot update.
        TransactionDetailStore.shared.softDelete(detailId: d2.txn_details_id)

        let bottle1 = BottleInfo(
            lotNumber: "LOT1", expirationDate: nil, serialNumber: nil,
            txnDetailsIds: [d1.txn_details_id, d2.txn_details_id], scannedAt: 1
        )
        let bottle2 = BottleInfo(
            lotNumber: "LOT2", expirationDate: nil, serialNumber: nil,
            txnDetailsIds: [d3.txn_details_id], scannedAt: 2
        )
        TransactionStore.shared.setBottleList(txnId: txn.txn_id, [bottle1, bottle2])

        let refreshedTxn = TransactionStore.shared.fetchById(txn.txn_id)!
        let message = HL7CompletionBuilder().buildCompletionMessage(txn: refreshedTxn, user: fixture.user)
        let rows = zsnSegments(in: message)

        #expect(rows.count == 2)
        // Bottle #1 sums only d1 (10) — d2 is soft-deleted so is excluded.
        #expect(rows[0][2] == "10")
        #expect(rows[0][6] == "LOT1")
        // Bottle #2 sums d3 (30) untouched.
        #expect(rows[1][2] == "30")
        #expect(rows[1][6] == "LOT2")
    }

    @Test func bottleReferencingDetailIdNotInPassedDetailsIsExcludedWithoutCrash() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let d1 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 10)!
        let phantomDetailId: Int64 = d1.txn_details_id + 999_999

        let bottle = BottleInfo(
            lotNumber: "LOT1", expirationDate: nil, serialNumber: nil,
            txnDetailsIds: [d1.txn_details_id, phantomDetailId], scannedAt: 1
        )
        TransactionStore.shared.setBottleList(txnId: txn.txn_id, [bottle])

        let refreshedTxn = TransactionStore.shared.fetchById(txn.txn_id)!
        let message = HL7CompletionBuilder().buildCompletionMessage(txn: refreshedTxn, user: fixture.user)
        let rows = zsnSegments(in: message)

        #expect(rows.count == 1)
        // Phantom id contributes 0 — only d1's 10 pills count.
        #expect(rows[0][2] == "10")
    }

    @Test func bottleOrderFollowsBottleListOrder() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let d1 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 1)!
        let d2 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 2)!
        let d3 = TransactionDetailStore.shared.add(txnId: txn.txn_id, pillCount: 3)!

        let bottleA = BottleInfo(lotNumber: "A", expirationDate: nil, serialNumber: nil, txnDetailsIds: [d1.txn_details_id], scannedAt: 1)
        let bottleB = BottleInfo(lotNumber: "B", expirationDate: nil, serialNumber: nil, txnDetailsIds: [d2.txn_details_id], scannedAt: 2)
        let bottleC = BottleInfo(lotNumber: "C", expirationDate: nil, serialNumber: nil, txnDetailsIds: [d3.txn_details_id], scannedAt: 3)
        TransactionStore.shared.setBottleList(txnId: txn.txn_id, [bottleA, bottleB, bottleC])

        let refreshedTxn = TransactionStore.shared.fetchById(txn.txn_id)!
        let message = HL7CompletionBuilder().buildCompletionMessage(txn: refreshedTxn, user: fixture.user)
        let rows = zsnSegments(in: message)

        #expect(rows.map { $0[6] } == ["A", "B", "C"])
    }
}
