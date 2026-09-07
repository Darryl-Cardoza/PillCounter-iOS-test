//
//  BottleInfoStoreTests.swift
//  PillCounterTests
//
//  Tests for BottleInfoStore.fetchByStockTxn(stockTxnId:in:). Runs against
//  the real on-disk CoreData store (see SQLiteCoreDataStack.swift for why);
//  every fixture is uniquely-id'd and torn down at the end of each test.
//

import CoreData
import Testing
@testable import PillCounter

@Suite(.serialized)
struct BottleInfoStoreTests {

    @Test func fetchByStockTxnInContextMatchesDefaultContextResult() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)
        let bottle = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 30, lotNo: "L1", expNo: "12-2027")
        defer { if let bottle { BottleInfoStore.shared.softDelete(bottleId: bottle.bottle_id) } }

        let context = CoreDataManager.shared.context
        let viaContext = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id, in: context)
        let viaDefault = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)

        #expect(Set(viaContext.map { $0.bottle_id }) == Set(viaDefault.map { $0.bottle_id }))
        #expect(viaContext.first?.bottle_qty == 30)
    }

    @Test func fetchByStockTxnInContextReturnsEmptyForStockTxnWithNoBottles() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let context = CoreDataManager.shared.context
        #expect(BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id, in: context).isEmpty)
    }

    // MARK: - Per-lot sealed rows

    /// Two sealed scans with different lot/exp on the same StockTxn must produce two
    /// independent BottleInfoEntity rows, not overwrite each other.
    @Test func setSealedBottleQtyCreatesSeparateRowsForDifferentLots() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let lotA = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 3, lotNo: "LOT-A", expNo: "2027-01")
        let lotB = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 2, lotNo: "LOT-B", expNo: "2027-06")
        defer {
            if let lotA { BottleInfoStore.shared.softDelete(bottleId: lotA.bottle_id) }
            if let lotB { BottleInfoStore.shared.softDelete(bottleId: lotB.bottle_id) }
        }

        #expect(lotA?.bottle_id != lotB?.bottle_id)
        let rows = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
        #expect(rows.count == 2)
        #expect(rows.reduce(0) { $0 + $1.bottle_qty } == 5)
    }

    /// A second sealed scan matching an existing row's exact (lot, exp) updates that
    /// row in place instead of creating a new one.
    @Test func setSealedBottleQtyUpdatesInPlaceForSameLot() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let first = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 3, lotNo: "LOT-A", expNo: "2027-01")
        let second = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 7, lotNo: "LOT-A", expNo: "2027-01")
        defer { if let second { BottleInfoStore.shared.softDelete(bottleId: second.bottle_id) } }

        #expect(first?.bottle_id == second?.bottle_id)
        let rows = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
        #expect(rows.count == 1)
        #expect(rows.first?.bottle_qty == 7)
    }

    /// Repeated scans with no lot/exp info (empty string) pool into the same row rather
    /// than spawning a new row per scan.
    @Test func setSealedBottleQtyPoolsRepeatedEmptyLotScansIntoOneRow() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let first = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 1, lotNo: "", expNo: "")
        let second = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 4, lotNo: "", expNo: "")
        defer { if let second { BottleInfoStore.shared.softDelete(bottleId: second.bottle_id) } }

        #expect(first?.bottle_id == second?.bottle_id)
        let rows = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
        #expect(rows.count == 1)
        #expect(rows.first?.bottle_qty == 4)
    }

    // MARK: - Open-pill image paths

    @Test func encodeDecodeImagesRoundTrips() {
        let images = [BottleImageRecord(path: "a.jpg", count: 5), BottleImageRecord(path: "b.jpg", count: 10)]
        let json = BottleInfoEntity.encodeImages(images)
        #expect(BottleInfoEntity.decodeImages(json) == images)
    }

    @Test func decodeImagesReturnsEmptyForNilOrInvalidJson() {
        #expect(BottleInfoEntity.decodeImages(nil).isEmpty)
        #expect(BottleInfoEntity.decodeImages("not json").isEmpty)
    }

    @Test func encodeImagesReturnsNilForEmptyArray() {
        #expect(BottleInfoEntity.encodeImages([]) == nil)
    }

    /// addOpenedBottle persists the captured images (path + count) on the new row.
    @Test func addOpenedBottleStoresImages() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let bottle = BottleInfoStore.shared.addOpenedBottle(
            stockTxnId: stockTxn.stock_txn_id, looseQty: 5, lotNo: "LOT-A", expNo: "2027-01",
            serialNo: nil, images: [BottleImageRecord(path: "img1.jpg", count: 5)]
        )
        defer { if let bottle { BottleInfoStore.shared.softDelete(bottleId: bottle.bottle_id) } }

        #expect(bottle?.images == [BottleImageRecord(path: "img1.jpg", count: 5)])
    }

    /// appendImages merges new images onto an existing row's array rather than
    /// overwriting it — repeated Add taps for the same lot/exp keep every snapshot.
    @Test func appendImagesMergesOntoExistingRow() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let bottle = BottleInfoStore.shared.addOpenedBottle(
            stockTxnId: stockTxn.stock_txn_id, looseQty: 5, lotNo: "LOT-A", expNo: "2027-01",
            serialNo: nil, images: [BottleImageRecord(path: "img1.jpg", count: 5)]
        )
        defer { if let bottle { BottleInfoStore.shared.softDelete(bottleId: bottle.bottle_id) } }
        guard let bottle else { Issue.record("expected bottle"); return }

        BottleInfoStore.shared.appendImages(bottleId: bottle.bottle_id, images: [BottleImageRecord(path: "img2.jpg", count: 3)])

        let refetched = BottleInfoStore.shared.fetchById(bottle.bottle_id)
        #expect(refetched?.images == [
            BottleImageRecord(path: "img1.jpg", count: 5), BottleImageRecord(path: "img2.jpg", count: 3)
        ])
    }

    /// fetchOpenedRow finds an existing opened row by exact (stockTxnId, lot, exp) and
    /// ignores sealed rows / rows with a different lot or exp.
    @Test func fetchOpenedRowMatchesExactLotExpAndIgnoresSealedRows() {
        let fixture = BatchTrackingFixture()
        defer { fixture.cleanUp() }
        let batch = fixture.makeBatch()
        let stockTxn = fixture.makeStockTxn(batch: batch)

        let sealed = BottleInfoStore.shared.setSealedBottleQty(stockTxnId: stockTxn.stock_txn_id, bottleQty: 1, lotNo: "LOT-A", expNo: "2027-01")
        let opened = BottleInfoStore.shared.addOpenedBottle(
            stockTxnId: stockTxn.stock_txn_id, looseQty: 5, lotNo: "LOT-A", expNo: "2027-01",
            serialNo: nil, images: []
        )
        defer {
            if let sealed { BottleInfoStore.shared.softDelete(bottleId: sealed.bottle_id) }
            if let opened { BottleInfoStore.shared.softDelete(bottleId: opened.bottle_id) }
        }

        let found = BottleInfoStore.shared.fetchOpenedRow(stockTxnId: stockTxn.stock_txn_id, lotNo: "LOT-A", expNo: "2027-01")
        #expect(found?.bottle_id == opened?.bottle_id)

        let notFound = BottleInfoStore.shared.fetchOpenedRow(stockTxnId: stockTxn.stock_txn_id, lotNo: "LOT-B", expNo: "2027-01")
        #expect(notFound == nil)
    }
}
