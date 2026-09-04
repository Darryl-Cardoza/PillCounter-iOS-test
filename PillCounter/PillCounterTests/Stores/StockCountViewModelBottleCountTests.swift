//
//  StockCountViewModelBottleCountTests.swift
//  PillCounterTests
//
//  Regression coverage for the per-lot sealed-row double-count bug: scanning a
//  second lot for an NDC that already has a sealed lot must not inflate
//  pendingBottleCount/displayBottleTotal by re-adding the first lot's count.
//

import CoreData
import Testing
@testable import PillCounter

@Suite(.serialized)
@MainActor
struct StockCountViewModelBottleCountTests {

    @Test func scanningSecondLotDoesNotDoubleCountFirstLot() async {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        // LOT-A already has 3 sealed bottles committed.
        let lotA = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 3, lotNo: "LOT-A", expNo: "2027-01")
        defer { if let lotA { BottleInfoStore.shared.softDelete(bottleId: lotA.bottle_id) } }

        let vm = StockCountViewModel()
        vm.currentBatch = batch

        // Per-lot lookup for a lot with no row yet must be 0, not the NDC-wide sum.
        #expect(vm.existingBottleCount(for: fixture.drug.ndc ?? "", lotNo: "LOT-B", expNo: "2027-06") == 0)
        // NDC-wide sum is still 3 (LOT-A only).
        #expect(vm.existingBottleCount(for: fixture.drug.ndc ?? "") == 3)

        // Simulate what fetchDrugDataOnly does when scanning LOT-B for the first time:
        // seed pendingBottleCount from the PER-LOT count (0) + 1, not the NDC-wide sum + 1.
        vm.committedLotNo = "LOT-B"
        vm.committedExpNo = "2027-06"
        vm.committedStockTxnId = stockTxn.stock_txn_id
        vm.pendingBottleCount = vm.existingBottleCount(for: fixture.drug.ndc ?? "", lotNo: "LOT-B", expNo: "2027-06") + 1

        #expect(vm.pendingBottleCount == 1, "Scanning a brand-new lot must seed pendingBottleCount at 1, not NDC-wide-sum + 1")

        // displayBottleTotal must combine LOT-A's committed 3 + the live LOT-B pending 1 = 4,
        // not 3 (LOT-A, counted once) + 4 (LOT-A's total mistakenly reused as LOT-B's pending).
        let total = vm.displayBottleTotal(for: fixture.drug.ndc ?? "")
        #expect(total == 4, "Expected sealed total 3 (LOT-A) + 1 (new LOT-B) = 4, got \(total)")
    }

    /// The scanned-drug-details screen shows sealed bottle count only — open (loose) pills
    /// must never be folded into that number, even though they exist on the same StockTxn.
    @Test func displayBottleTotalExcludesOpenPills() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let sealed = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 3, lotNo: "LOT-A", expNo: "2027-01")
        let opened = BottleInfoStore.shared.addOpenedBottle(stockTxnId: stockTxn.stock_txn_id, looseQty: 15, lotNo: "LOT-A", expNo: "2027-01", serialNo: nil)
        defer {
            if let sealed { BottleInfoStore.shared.softDelete(bottleId: sealed.bottle_id) }
            if let opened { BottleInfoStore.shared.softDelete(bottleId: opened.bottle_id) }
        }

        let vm = StockCountViewModel()
        vm.currentBatch = batch
        vm.committedStockTxnId = stockTxn.stock_txn_id
        vm.committedLotNo = "LOT-A"
        vm.committedExpNo = "2027-01"
        vm.committedBottleId = sealed?.bottle_id
        vm.pendingBottleCount = 3

        #expect(vm.existingOpenPillCount(for: fixture.drug.ndc ?? "") == 15)
        #expect(vm.displayBottleTotal(for: fixture.drug.ndc ?? "") == 3, "Open pills must not be counted as sealed bottles")
    }

    @Test func flushWritesNewLotAsSeparateRowNotOverwritingFirstLot() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let lotA = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 3, lotNo: "LOT-A", expNo: "2027-01")
        defer {
            if let lotA { BottleInfoStore.shared.softDelete(bottleId: lotA.bottle_id) }
        }

        let vm = StockCountViewModel()
        vm.currentBatch = batch
        vm.committedStockTxnId = stockTxn.stock_txn_id
        vm.committedLotNo = "LOT-B"
        vm.committedExpNo = "2027-06"
        vm.pendingBottleCount = 1

        vm.flushPendingBottleCount()

        let rows = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
        defer {
            for row in rows where row.lot_no == "LOT-B" {
                BottleInfoStore.shared.softDelete(bottleId: row.bottle_id)
            }
        }
        #expect(rows.count == 2, "Flushing a new lot must create a second row, not overwrite LOT-A's row")
        #expect(rows.first { $0.lot_no == "LOT-A" }?.bottle_qty == 3)
        #expect(rows.first { $0.lot_no == "LOT-B" }?.bottle_qty == 1)
    }
}
