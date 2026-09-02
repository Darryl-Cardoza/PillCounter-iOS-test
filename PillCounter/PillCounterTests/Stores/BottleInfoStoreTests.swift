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
}
