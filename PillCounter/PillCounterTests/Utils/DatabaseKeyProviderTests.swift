//
//  DatabaseKeyProviderTests.swift
//  PillCounterTests
//
//  DatabaseKeyProvider is a hardwired singleton over the real Keychain/
//  AppStorage (matching how CoreDataManager.shared is tested elsewhere) —
//  each test clears the DEK metadata it touches before and after so runs
//  don't leak into each other. Serialized for the same reason.
//
//  Covers both DEK slots — `.field` (FieldEncryptionManager) and `.image`
//  (PhotoFileManager) — since `rotateKekIfNewer` rotates both in one call.
//

import Testing
import Foundation
@testable import PillCounter

@Suite(.serialized)
struct DatabaseKeyProviderTests {

    private func resetDekState(_ slot: DekSlot) {
        let storage = AppStorageManager.shared
        if let kekId = storage.string(forKey: slot.kekIdStorageKey) {
            KekDekManager.shared.deleteKey(alias: kekId == "local-bootstrap"
                ? slot.bootstrapAlias
                : slot.serverAliasPrefix + kekId)
        }
        storage.setString(nil, forKey: slot.wrappedStorageKey)
        storage.setString(nil, forKey: slot.kekIdStorageKey)
        storage.setInt(-1, forKey: slot.kekVersionStorageKey)
    }

    private func resetAllDekState() {
        resetDekState(.field)
        resetDekState(.image)
        DatabaseKeyProvider.shared.resetCacheForTesting()
    }

    @Test func getOrCreateDekIsStableAcrossRepeatedCalls() {
        resetAllDekState()
        defer { resetAllDekState() }

        let first = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)
        let second = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)

        #expect(first == second)
    }

    @Test func fieldAndImageDeksAreIndependent() {
        resetAllDekState()
        defer { resetAllDekState() }

        let fieldDek = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)
        let imageDek = DatabaseKeyProvider.shared.getOrCreateDek(for: .image)

        #expect(fieldDek != imageDek)
    }

    @Test func rotationChangesWrapperNotTheDekForBothSlots() {
        resetAllDekState()
        defer {
            let storage = AppStorageManager.shared
            storage.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.field.serverAliasPrefix + $0)
            }
            storage.string(forKey: DekSlot.image.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.image.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        let fieldDekBefore = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)
        let imageDekBefore = DatabaseKeyProvider.shared.getOrCreateDek(for: .image)

        let rawKek = Data(repeating: 0x11, count: 32)
        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "server-key-1", version: 1, keyMaterial: rawKek.base64EncodedString())
        )

        let storage = AppStorageManager.shared
        #expect(DatabaseKeyProvider.shared.getOrCreateDek(for: .field) == fieldDekBefore)
        #expect(DatabaseKeyProvider.shared.getOrCreateDek(for: .image) == imageDekBefore)
        #expect(storage.string(forKey: DekSlot.field.kekIdStorageKey) == "server-key-1")
        #expect(storage.int(forKey: DekSlot.field.kekVersionStorageKey) == 1)
        #expect(storage.string(forKey: DekSlot.image.kekIdStorageKey) == "server-key-1")
        #expect(storage.int(forKey: DekSlot.image.kekVersionStorageKey) == 1)
    }

    @Test func rotationToLowerOrEqualVersionIsNoOp() {
        resetAllDekState()
        defer {
            AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.field.serverAliasPrefix + $0)
            }
            AppStorageManager.shared.string(forKey: DekSlot.image.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.image.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        _ = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)
        let rawKek = Data(repeating: 0x22, count: 32)
        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "server-key-2", version: 2, keyMaterial: rawKek.base64EncodedString())
        )

        // Duplicate /auth/me response with the same or an older version.
        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "server-key-2", version: 2, keyMaterial: rawKek.base64EncodedString())
        )
        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "server-key-stale", version: 1, keyMaterial: rawKek.base64EncodedString())
        )

        let storage = AppStorageManager.shared
        #expect(storage.string(forKey: DekSlot.field.kekIdStorageKey) == "server-key-2")
        #expect(storage.int(forKey: DekSlot.field.kekVersionStorageKey) == 2)
        #expect(!KekDekManager.shared.keyExists(alias: DekSlot.field.serverAliasPrefix + "server-key-stale"))
    }

    @Test func sequentialRotationDeletesOnlyThePriorAlias() {
        resetAllDekState()
        defer {
            AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.field.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        _ = DatabaseKeyProvider.shared.getOrCreateDek(for: .field) // bootstrap alias created

        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "seq-1", version: 1, keyMaterial: Data(repeating: 0x33, count: 32).base64EncodedString())
        )
        #expect(!KekDekManager.shared.keyExists(alias: DekSlot.field.bootstrapAlias))

        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "seq-2", version: 2, keyMaterial: Data(repeating: 0x44, count: 32).base64EncodedString())
        )
        #expect(!KekDekManager.shared.keyExists(alias: DekSlot.field.serverAliasPrefix + "seq-1"))
        #expect(KekDekManager.shared.keyExists(alias: DekSlot.field.serverAliasPrefix + "seq-2"))
    }

    @Test func malformedRotationPayloadLeavesExistingDekUntouched() {
        resetAllDekState()
        defer { resetAllDekState() }

        let dekBefore = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)
        let storage = AppStorageManager.shared
        let kekIdBefore = storage.string(forKey: DekSlot.field.kekIdStorageKey)
        let wrappedBefore = storage.string(forKey: DekSlot.field.wrappedStorageKey)

        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "bad-payload", version: 1, keyMaterial: "not valid base64!!")
        )

        #expect(storage.string(forKey: DekSlot.field.kekIdStorageKey) == kekIdBefore)
        #expect(storage.string(forKey: DekSlot.field.wrappedStorageKey) == wrappedBefore)
        #expect(DatabaseKeyProvider.shared.getOrCreateDek(for: .field) == dekBefore)
    }

    // Recovery from an unrecoverable field DEK calls CoreDataManager.shared
    // .destroyAndReloadStore(), which wipes the real on-disk app database —
    // deliberately not exercised here against the production singleton.
    // Covered instead at the primitive level by KekDekManagerTests
    // (unwrap-with-missing-key throws, never auto-creates a substitute key)
    // and by CoreDataManagerTests for destroyAndReloadStore itself.
}
