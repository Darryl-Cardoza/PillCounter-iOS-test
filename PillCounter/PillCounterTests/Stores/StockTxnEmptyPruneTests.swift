//
//  StockTxnEmptyPruneTests.swift
//  PillCounterTests
//
//  Reproduces the reported bug: zeroing out every lot/exp row for an NDC in the
//  edit sheet should soft-delete that NDC's StockTxn — for every NDC in a batch,
//  not just the first one touched. Mirrors StockCountEditDetailsSheet's
//  pruneZeroedRowsAndEmptyTxn against the real on-disk store (multiple NDCs
//  share one BatchCountEntity, exactly like a real stock-count session).
//

import CoreData
import Testing
@testable import PillCounter

@Suite(.serialized)
struct StockTxnEmptyPruneTests {

    /// Mirrors StockCountEditDetailsSheet.pruneZeroedRowsAndEmptyTxn: zero every
    /// bottle row for a StockTxn, soft-delete the zeroed bottles, then soft-delete
    /// the StockTxn itself once no bottles remain.
    private func zeroAndPrune(stockTxnId: Int64) {
        let bottles = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxnId)
        for bottle in bottles {
            BottleInfoStore.shared.setAbsolute(bottleId: bottle.bottle_id, bottleQty: 0, looseQty: 0)
        }
        let zeroed = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxnId)
        for bottle in zeroed where bottle.bottle_qty == 0 && bottle.loose_qty == 0 {
            BottleInfoStore.shared.softDelete(bottleId: bottle.bottle_id)
        }
        let remaining = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxnId)
        guard remaining.isEmpty else { return }
        StockTxnStore.shared.softDelete(stockTxnId: stockTxnId)
    }

    /// Two NDCs in one batch. Zeroing the FIRST NDC's only lot must soft-delete
    /// its StockTxn. Zeroing the SECOND NDC's only lot — same batch, same shared
    /// viewContext, right after the first prune ran — must ALSO soft-delete its
    /// StockTxn. Before the fix, the second prune's `remaining` fetch kept
    /// returning the just-soft-deleted bottle row from the first NDC (stale
    /// context registration from the batch-delete request), which could make
    /// this false-negative depending on Core Data's row cache state.
    @Test func secondNdcInSameBatchAlsoPrunesToDeletedAfterZeroing() {
        let fixtureA = BatchTrackingFixture()
        let fixtureB = BatchTrackingFixture()
        defer {
            fixtureA.cleanUp()
            fixtureB.cleanUp()
        }

        let batch = fixtureA.makeBatch()
        // Same batch_id for both fixtures' stock txns — two NDCs in one batch.
        let stockTxnA = StockTxnStore.shared.fetchOrCreate(batch: batch, drugId: fixtureA.drugId, bucketId: batch.bucket_id)
        let stockTxnB = StockTxnStore.shared.fetchOrCreate(batch: batch, drugId: fixtureB.drugId, bucketId: batch.bucket_id)

        BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxnA.stock_txn_id, bottleQty: 4, lotNo: "LOT-A", expNo: "2027-01")
        BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxnB.stock_txn_id, bottleQty: 4, lotNo: "LOT-B", expNo: "2027-01")

        zeroAndPrune(stockTxnId: stockTxnA.stock_txn_id)
        #expect(StockTxnStore.shared.fetchById(stockTxnA.stock_txn_id)?.is_deleted == true)

        zeroAndPrune(stockTxnId: stockTxnB.stock_txn_id)
        #expect(StockTxnStore.shared.fetchById(stockTxnB.stock_txn_id)?.is_deleted == true, "second NDC's StockTxn must also be soft-deleted once its only lot is zeroed")

        let liveStockTxns = StockTxnStore.shared.fetchByBatch(batchId: batch.batch_id)
        #expect(liveStockTxns.isEmpty, "no live (non-deleted) StockTxn rows should remain for this batch")

        let counts = BatchStore.shared.transactionCounts(for: [batch.batch_id])
        #expect(counts[batch.batch_id] == 0, "dashboard NDC count must not include soft-deleted StockTxn rows")
    }

    /// Same scenario with a THIRD NDC, and pruning in a different order (B then A then C) —
    /// guards against a fix that happens to work only for exactly two NDCs or only when
    /// pruned in creation order.
    @Test func thirdNdcInSameBatchPrunesRegardlessOfOrder() {
        let fixtureA = BatchTrackingFixture()
        let fixtureB = BatchTrackingFixture()
        let fixtureC = BatchTrackingFixture()
        defer {
            fixtureA.cleanUp()
            fixtureB.cleanUp()
            fixtureC.cleanUp()
        }

        let batch = fixtureA.makeBatch()
        let stockTxnA = StockTxnStore.shared.fetchOrCreate(batch: batch, drugId: fixtureA.drugId, bucketId: batch.bucket_id)
        let stockTxnB = StockTxnStore.shared.fetchOrCreate(batch: batch, drugId: fixtureB.drugId, bucketId: batch.bucket_id)
        let stockTxnC = StockTxnStore.shared.fetchOrCreate(batch: batch, drugId: fixtureC.drugId, bucketId: batch.bucket_id)

        BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxnA.stock_txn_id, bottleQty: 2, lotNo: "LOT-A", expNo: "2027-01")
        BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxnB.stock_txn_id, bottleQty: 3, lotNo: "LOT-B", expNo: "2027-01")
        BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxnC.stock_txn_id, bottleQty: 4, lotNo: "LOT-C", expNo: "2027-01")

        zeroAndPrune(stockTxnId: stockTxnB.stock_txn_id)
        zeroAndPrune(stockTxnId: stockTxnA.stock_txn_id)
        zeroAndPrune(stockTxnId: stockTxnC.stock_txn_id)

        #expect(StockTxnStore.shared.fetchById(stockTxnA.stock_txn_id)?.is_deleted == true)
        #expect(StockTxnStore.shared.fetchById(stockTxnB.stock_txn_id)?.is_deleted == true)
        #expect(StockTxnStore.shared.fetchById(stockTxnC.stock_txn_id)?.is_deleted == true)

        let counts = BatchStore.shared.transactionCounts(for: [batch.batch_id])
        #expect(counts[batch.batch_id] == 0)
    }

    /// softDeleteByStockTxn (the cascade StockTxnStore.softDelete triggers) must remove
    /// every bottle row for that StockTxn in one call — not just a single targeted bottleId.
    @Test func softDeleteByStockTxnRemovesAllBottlesForThatStockTxn() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = StockTxnStore.shared.fetchOrCreate(batch: batch, drugId: fixture.drugId, bucketId: batch.bucket_id)

        BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 2, lotNo: "LOT-A", expNo: "2027-01")
        BottleInfoStore.shared.addOpenedBottle(stockTxnId: stockTxn.stock_txn_id, looseQty: 5, lotNo: "LOT-B", expNo: "2027-06", serialNo: nil)
        #expect(BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id).count == 2)

        BottleInfoStore.shared.softDeleteByStockTxn(stockTxnId: stockTxn.stock_txn_id)

        #expect(BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id).isEmpty)
    }
}
