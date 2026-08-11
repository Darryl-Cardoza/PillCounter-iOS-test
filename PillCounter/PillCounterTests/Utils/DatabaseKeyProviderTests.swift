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

    /// Regression test for a real bug found in review: bootstrap sets
    /// kekVersionStorageKey to 0, so a strict `>` comparison meant a
    /// server's legitimate FIRST KEK at version 0 could never rotate in
    /// (0 > 0 is false) — the device would be silently stuck on the
    /// bootstrap KEK forever. Fixed by treating "still on bootstrap" as
    /// always eligible for the first server KEK, regardless of its version.
    @Test func firstServerKekAtVersionZeroStillRotatesIn() {
        resetAllDekState()
        defer {
            AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.field.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        let dekBefore = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)

        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "server-key-zero", version: 0, keyMaterial: Data(repeating: 0x55, count: 32).base64EncodedString())
        )

        let storage = AppStorageManager.shared
        #expect(storage.string(forKey: DekSlot.field.kekIdStorageKey) == "server-key-zero")
        #expect(storage.int(forKey: DekSlot.field.kekVersionStorageKey) == 0)
        #expect(DatabaseKeyProvider.shared.getOrCreateDek(for: .field) == dekBefore)
    }

    /// Once already on a server KEK (even at version 0), a duplicate/older
    /// version must still be a no-op — the version-0 fix must not regress
    /// this into "always rotate when kekId changes."
    @Test func afterFirstServerKekOnlyStrictlyHigherVersionRotates() {
        resetAllDekState()
        defer {
            AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.field.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        _ = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)
        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "server-key-zero", version: 0, keyMaterial: Data(repeating: 0x66, count: 32).base64EncodedString())
        )

        // Same version, different key id — must NOT rotate (would silently
        // discard the current KEK for no reason if the guard regressed).
        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "server-key-zero-duplicate", version: 0, keyMaterial: Data(repeating: 0x77, count: 32).base64EncodedString())
        )

        let storage = AppStorageManager.shared
        #expect(storage.string(forKey: DekSlot.field.kekIdStorageKey) == "server-key-zero")
        #expect(!KekDekManager.shared.keyExists(alias: DekSlot.field.serverAliasPrefix + "server-key-zero-duplicate"))
    }

    /// Regression test: migrating a pre-existing legacy raw key must delete
    /// the old plaintext copy after wrapping it — leaving it behind was a
    /// dangling second exposure of the same key material found in review.
    @Test func migratingLegacyRawKeyDeletesTheOldPlaintextCopy() {
        resetAllDekState()
        let legacyAccount = "test.legacy.\(UUID().uuidString)"
        let legacyService = Keychain.defaultService
        let slot = DekSlot(
            bootstrapAlias: "test.legacy.bootstrap.\(UUID().uuidString)",
            serverAliasPrefix: "test.legacy.server_",
            wrappedStorageKey: "test_legacy_wrapped_\(UUID().uuidString)",
            kekIdStorageKey: "test_legacy_kekid_\(UUID().uuidString)",
            kekVersionStorageKey: "test_legacy_kekversion_\(UUID().uuidString)",
            legacyRawKeyAccount: legacyAccount,
            legacyRawKeyService: legacyService
        )
        defer {
            resetDekState(slot)
            Keychain.deleteData(account: legacyAccount, service: legacyService)
        }

        let legacyRawKey = Data(repeating: 0x99, count: 32)
        Keychain.setData(legacyRawKey, account: legacyAccount, service: legacyService)

        let dek = DatabaseKeyProvider.shared.getOrCreateDek(for: slot)

        #expect(dek.withUnsafeBytes { Data($0) } == legacyRawKey)
        #expect(Keychain.data(account: legacyAccount, service: legacyService) == nil)
    }
}
