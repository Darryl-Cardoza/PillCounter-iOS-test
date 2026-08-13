//
//  FaceUserStoreTests.swift
//  PillCounterTests
//
//  Runs against the real on-disk CoreData store via CoreDataManager.shared —
//  matches TransactionStoreTests. Every row is uniquely-id'd and torn down.
//

import Testing
@testable import PillCounter

@Suite(.serialized)
struct FaceUserStoreTests {

    @Test func insertUserPersistsAndFetchesById() {
        let id = UUID().uuidString
        let name = "Test User \(id.prefix(8))"
        defer { FaceUserStore.shared.deleteUser(id: id) }

        FaceUserStore.shared.insertUser(id: id, name: name)

        let fetched = FaceUserStore.shared.getUser(id: id)
        #expect(fetched?.name == name)
        #expect(fetched?.is_active == true)
    }

    @Test func isNameTakenIsCaseInsensitiveAndActiveOnly() {
        let id = UUID().uuidString
        let name = "Dup Check \(id.prefix(8))"
        defer { FaceUserStore.shared.deleteUser(id: id) }

        #expect(FaceUserStore.shared.isNameTaken(name) == false)

        FaceUserStore.shared.insertUser(id: id, name: name)

        #expect(FaceUserStore.shared.isNameTaken(name) == true)
        #expect(FaceUserStore.shared.isNameTaken(name.uppercased()) == true)
    }

    @Test func deactivateUserRemovesFromActiveList() {
        let id = UUID().uuidString
        let name = "Deactivate Me \(id.prefix(8))"
        defer { FaceUserStore.shared.deleteUser(id: id) }

        FaceUserStore.shared.insertUser(id: id, name: name)
        #expect(FaceUserStore.shared.isNameTaken(name) == true)

        FaceUserStore.shared.deactivateUser(id: id)

        #expect(FaceUserStore.shared.isNameTaken(name) == false)
        #expect(FaceUserStore.shared.getUser(id: id)?.is_active == false)
    }

    @Test func deleteUserRemovesRow() {
        let id = UUID().uuidString
        FaceUserStore.shared.insertUser(id: id, name: "Delete Me")

        FaceUserStore.shared.deleteUser(id: id)

        #expect(FaceUserStore.shared.getUser(id: id) == nil)
    }
}
