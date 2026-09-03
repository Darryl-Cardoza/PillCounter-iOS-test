//
//  BaseDataStoreTests.swift
//  PillCounterTests
//

import CoreData
import Testing
@testable import PillCounter

/// Minimal concrete subclass exercising BaseDataStore against the real
/// PillCountTransactionEntity model — mirrors how TransactionStore etc.
/// subclass it, but with no entity-specific methods, so these tests isolate
/// the base class's own behavior.
private final class ProbeStore: BaseDataStore<PillCountTransactionEntity> {
    static let shared = ProbeStore()
    var postFetchCallCount = 0

    override func postFetch(_ entity: PillCountTransactionEntity) {
        postFetchCallCount += 1
    }
}

@Suite(.serialized)
struct BaseDataStoreTests {

    @Test func fetchOneReturnsNilWhenNoMatch() {
        let store = ProbeStore.shared
        let predicate = NSPredicate(format: "txn_id == %lld", Int64.max)
        let result = store.sync {
            store.fetchOne(predicate: predicate, sort: nil, in: store.context)
        }
        #expect(result == nil)
    }

    @Test func fetchOneFindsCreatedEntityAndCallsPostFetch() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let store = ProbeStore.shared
        store.postFetchCallCount = 0
        let predicate = NSPredicate(format: "txn_id == %lld", txn.txn_id)
        let result = store.sync {
            store.fetchOne(predicate: predicate, sort: nil, in: store.context)
        }
        #expect(result?.txn_id == txn.txn_id)
        #expect(store.postFetchCallCount == 1)
    }

    @Test func fetchPageRespectsLimitAndOffset() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let ids = (0..<5).map { _ in fixture.makeTransaction().txn_id }

        let store = ProbeStore.shared
        let predicate = NSPredicate(format: "txn_id IN %@", ids)
        let sort = [NSSortDescriptor(key: "txn_id", ascending: true)]

        let firstPage = store.sync {
            store.fetchPage(predicate: predicate, sort: sort, limit: 2, offset: 0, in: store.context)
        }
        let secondPage = store.sync {
            store.fetchPage(predicate: predicate, sort: sort, limit: 2, offset: 2, in: store.context)
        }
        #expect(firstPage.count == 2)
        #expect(secondPage.count == 2)
        #expect(firstPage.map(\.txn_id) != secondPage.map(\.txn_id))
    }

    @Test func fetchPageReturnsEmptyPastEnd() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let txn = fixture.makeTransaction()

        let store = ProbeStore.shared
        let predicate = NSPredicate(format: "txn_id == %lld", txn.txn_id)
        let page = store.sync {
            store.fetchPage(predicate: predicate, sort: nil, limit: 10, offset: 5, in: store.context)
        }
        #expect(page.isEmpty)
    }

    @Test func fetchAllMatchingReturnsEveryRow() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }
        let ids = (0..<3).map { _ in fixture.makeTransaction().txn_id }

        let store = ProbeStore.shared
        let predicate = NSPredicate(format: "txn_id IN %@", ids)
        let results = store.sync {
            store.fetchAllMatching(predicate: predicate, sort: nil, in: store.context)
        }
        #expect(Set(results.map(\.txn_id)) == Set(ids))
    }

    @Test func syncRunsBlockOnContextQueue() {
        let store = ProbeStore.shared
        var ran = false
        store.sync { ran = true }
        #expect(ran)
    }
}
