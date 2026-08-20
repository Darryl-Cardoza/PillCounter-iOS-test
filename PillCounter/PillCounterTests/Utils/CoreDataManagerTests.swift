//
//  CoreDataManagerTests.swift
//  PillCounterTests
//
//  Exercises destroyAndReloadStore() against a private in-memory
//  CoreDataManager instance — never against .shared, which is the same
//  on-disk store other suites' fixtures read/write.
//

import Testing
import CoreData
@testable import PillCounter

@Suite
struct CoreDataManagerTests {

    @Test func destroyAndReloadStoreClearsExistingDataAndStoreStaysUsable() {
        let manager = CoreDataManager(inMemory: true)

        let entity = UserEntity(context: manager.context)
        entity.user_id = "kek-dek-test-user"
        entity.created_at = Date()
        manager.save(context: manager.context)

        let fetchBefore = UserEntity.fetchRequest()
        #expect(((try? manager.context.count(for: fetchBefore)) ?? 0) == 1)

        manager.destroyAndReloadStore()

        let fetchAfter = UserEntity.fetchRequest()
        #expect(((try? manager.context.count(for: fetchAfter)) ?? -1) == 0)

        // Store is still usable after being destroyed and reloaded.
        let entity2 = UserEntity(context: manager.context)
        entity2.user_id = "kek-dek-test-user-2"
        entity2.created_at = Date()
        manager.save(context: manager.context)

        #expect(((try? manager.context.count(for: UserEntity.fetchRequest())) ?? 0) == 1)
    }
}
