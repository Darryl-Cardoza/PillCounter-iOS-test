//
//  UserStoreTests.swift
//  PillCounterTests
//
//  Tests for UserStore.fetchByUserId(_:in:). Runs against the real on-disk
//  CoreData store (see SQLiteCoreDataStack.swift for why); every fixture is
//  uniquely-id'd and torn down at the end of each test.
//

import CoreData
import Testing
@testable import PillCounter

@Suite(.serialized)
struct UserStoreTests {

    @Test func fetchByUserIdInContextMatchesDefaultContextResult() {
        let fixture = BottleTrackingFixture()
        defer { fixture.cleanUp() }

        let context = CoreDataManager.shared.context
        let viaContext = UserStore.shared.fetchByUserId(fixture.userId, in: context)
        let viaDefault = UserStore.shared.fetchByUserId(fixture.userId)

        #expect(viaContext?.user_id == fixture.userId)
        #expect(viaContext?.user_id == viaDefault?.user_id)
    }

    @Test func fetchByUserIdInContextReturnsNilForUnknownUser() {
        let context = CoreDataManager.shared.context
        #expect(UserStore.shared.fetchByUserId("nonexistent-\(TestIds.unique())", in: context) == nil)
    }
}
