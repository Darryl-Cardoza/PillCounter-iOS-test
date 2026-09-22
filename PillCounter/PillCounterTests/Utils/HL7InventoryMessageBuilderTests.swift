//
//  HL7InventoryMessageBuilderTests.swift
//  PillCounterTests
//
//  Covers buildInventoryMessage's grouping/filter logic (HL7MessageBuilder.swift)
//  and proves, against the real Hl7Core encoder, where observationValue2 lands in
//  the encoded OBX-5 field — the ../../swiftpackage source isn't in this checkout,
//  so this is the only way to verify component 2 (not OBX-6) carries the physical
//  bottle count.
//

import Testing
@testable import PillCounter

@Suite(.serialized)
struct HL7InventoryMessageBuilderTests {

    /// Splits a raw HL7 message into its OBX segments, each represented as its
    /// pipe-delimited fields (field 0 is the segment name "OBX").
    private func obxSegments(in message: String) -> [[String]] {
        message
            .components(separatedBy: "\r")
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { $0.hasPrefix("OBX") }
            .map { $0.components(separatedBy: "|") }
    }

    @Test func sealedAndOpenObxRowsCarryQtyInComponent1AndBottleCountInComponent2() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        DrugCatalogStore.shared.saveManual(
            ndc: fixture.drug.ndc ?? "", drugId: fixture.drugId,
            drugName: fixture.drug.drug_name ?? "", packageQty: 10
        )
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        // Two sealed bottles of the same lot/expiry (bottle_qty accumulates)
        // plus one opened bottle counted to 7 loose pills.
        let sealed = BottleInfoStore.shared.setSealedBottleQty(
            stockTxnId: stockTxn.stock_txn_id, bottleQty: 2, lotNo: "LOT-A", expNo: "2027-01"
        )
        let opened = BottleInfoStore.shared.addOpenedBottle(
            stockTxnId: stockTxn.stock_txn_id, looseQty: 7, lotNo: "LOT-B", expNo: "2027-06",
            serialNo: nil, images: []
        )
        defer {
            if let sealed { BottleInfoStore.shared.softDelete(bottleId: sealed.bottle_id) }
            if let opened { BottleInfoStore.shared.softDelete(bottleId: opened.bottle_id) }
        }

        let message = HL7CompletionBuilder().buildInventoryMessage(batch: batch, user: nil)
        let rows = obxSegments(in: message)

        // Sealed and opened bottles use different lot/expiry, so they land in
        // two separate INV groups — each group emits both a SEALED_QTY and an
        // OPEN_QTY row (zeroed on whichever side that group has none of).
        // Row shape: OBX|setId|valueType|observationId|subId|value|...
        let sealedRow = rows.first { $0[3] == "SEALED_QTY" && $0[5] != "0^0" }
        #expect(sealedRow != nil)
        // OBX-5 is field index 5; component 1 is pill qty (bottle_qty *
        // package_qty = 2 * 10), component 2 is physical bottle count (bottle_qty = 2).
        let sealedComponents = sealedRow?[5].components(separatedBy: "^")
        #expect(sealedComponents?[0] == "20")
        #expect(sealedComponents?[1] == "2")

        let openRow = rows.first { $0[3] == "OPEN_QTY" && $0[5] != "0^0" }
        #expect(openRow != nil)
        let openComponents = openRow?[5].components(separatedBy: "^")
        #expect(openComponents?[0] == "7")
        #expect(openComponents?[1] == "1")
    }

    @Test func sealedRowWithZeroPackageQtyStillReportedForItsBottleCount() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        // package_qty left at 0 — sealed pill qty is 0, but bottle_qty (2) is
        // still a real physical count that must not be filtered out.
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let sealed = BottleInfoStore.shared.setSealedBottleQty(
            stockTxnId: stockTxn.stock_txn_id, bottleQty: 2, lotNo: "LOT-A", expNo: "2027-01"
        )
        defer { if let sealed { BottleInfoStore.shared.softDelete(bottleId: sealed.bottle_id) } }

        let message = HL7CompletionBuilder().buildInventoryMessage(batch: batch, user: nil)
        let rows = obxSegments(in: message)

        let sealedRow = rows.first { $0[3] == "SEALED_QTY" }
        #expect(sealedRow != nil)
        let components = sealedRow?[5].components(separatedBy: "^")
        #expect(components?[0] == "0")
        #expect(components?[1] == "2")
    }

    @Test func openedRowWithZeroLooseQtyIsExcludedFromInventoryMessage() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        // Scanned as opened but never counted (looseQty 0) — carries nothing for
        // the PMS to act on, unlike a sealed row where bottle_qty alone is real
        // physical-count information.
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let opened = BottleInfoStore.shared.addOpenedBottle(
            stockTxnId: stockTxn.stock_txn_id, looseQty: 0, lotNo: "LOT-B", expNo: "2027-06",
            serialNo: nil, images: []
        )
        defer { if let opened { BottleInfoStore.shared.softDelete(bottleId: opened.bottle_id) } }

        let message = HL7CompletionBuilder().buildInventoryMessage(batch: batch, user: nil)
        let rows = obxSegments(in: message)

        #expect(rows.first { $0[3] == "OPEN_QTY" } == nil)
        #expect(rows.first { $0[3] == "SEALED_QTY" } == nil)
    }
}
