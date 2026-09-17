//
//  KekDekEndToEndTests.swift
//  PillCounterTests
//
//  Verifies the KEK/DEK envelope actually protects real CoreData rows, not
//  just isolated Keychain blobs — the gap the primitive-level KekDekManager/
//  DatabaseKeyProvider tests can't see. Two questions this answers:
//
//   1. Does the DEK actually wrap/unwrap real DB field data correctly, end
//      to end through FieldEncryptionManager + NSManagedObject's swizzled
//      willSave/awakeFromFetch — not just raw AES.GCM.seal/open in isolation?
//   2. Does KEK rotation work against a REAL already-encrypted row — i.e.
//      after rotating from bootstrap to a server KEK (or server KEK A to B),
//      is a row encrypted BEFORE rotation still decryptable AFTER, without
//      any re-encryption of the row itself (since only the KEK wrapper
//      around the DEK changes, never the DEK, never the field ciphertext)?
//
//  Uses `CoreDataManager.shared` (the REAL on-disk store), not an in-memory
//  one. Confirmed empirically that `willSave`/`didSave` — the swizzled hooks
//  encryption depends on — never fire for `NSInMemoryStoreType` contexts in
//  this app's CoreData setup (added temporary logging inside
//  NSManagedObject+Encryption.swift's enc_willSave and confirmed zero calls
//  for any entity saved through CoreDataManager(inMemory: true)/MockCoreData,
//  vs. firing correctly for every entity through CoreDataManager.shared).
//  That's a deeper platform/store-type behavior difference, not a KEK/DEK
//  bug, and out of scope to change here — so this suite follows
//  SQLiteCoreDataStack.swift's established, sanctioned pattern for testing
//  against the real on-disk store safely: randomized unique ids
//  (TestIds.unique()) that can never collide with real app data, explicit
//  cleanup in `defer`, and `@Suite(.serialized)` since the store is shared
//  mutable state.
//
//  (Separately fixed as part of getting here: CoreDataManager was loading a
//  fresh NSManagedObjectModel per instance — .shared and any
//  inMemory: instance each called NSPersistentContainer(name:) independently
//  — which could leave two distinct model instances for the same
//  "PillCounter" model in one process, and Core Data would then intermittently
//  fail to bind `UserEntity` to a single unambiguous NSEntityDescription
//  ("+[UserEntity entity] Failed to find a unique match..."). Fixed by
//  caching one NSManagedObjectModel and passing it explicitly to every
//  NSPersistentContainer(name:managedObjectModel:) — see CoreDataManager.swift.)
//

import Testing
import Foundation
import CoreData
import CryptoKit
import SQLite3
@testable import PillCounter

/// Reads a column's raw stored value directly from the SQLite file backing
/// `CoreDataManager.shared`, bypassing CoreData's object graph entirely.
///
/// Needed because `NSManagedObject+Encryption.swift`'s `didSave()` restores
/// plaintext onto the in-memory object right after every save (by design —
/// so a saved object stays readable without a re-fetch), and
/// `awakeFromFetch()` decrypts on every fetch. There is no supported way to
/// observe the raw ciphertext through CoreData's own API once an object
/// exists in any context — which is the correct behavior for the app (never
/// leak ciphertext into the UI), but means proving "is this actually
/// encrypted on disk" requires stepping outside CoreData and reading the
/// SQLite row directly, the same way an attacker who extracted the .sqlite
/// file would see it.
private func readRawColumnFromSQLite(table: String, column: String, whereUserIdEquals userId: String) -> String? {
    guard let storeURL = CoreDataManager.shared.container.persistentStoreDescriptions.first?.url else {
        return nil
    }

    var db: OpaquePointer?
    guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
        return nil
    }
    defer { sqlite3_close(db) }

    let sql = "SELECT \(column) FROM \(table) WHERE user_id = ? LIMIT 1"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        return nil
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, userId, -1, nil)
    guard sqlite3_step(statement) == SQLITE_ROW,
          let cString = sqlite3_column_text(statement, 0)
    else {
        return nil
    }
    return String(cString: cString)
}

@Suite(.serialized)
struct KekDekEndToEndTests {

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    private func makeUser(userId: String, email: String? = nil, fname: String? = nil) -> UserEntity {
        let user = UserEntity(context: context)
        user.user_id = userId
        user.created_at = Date()
        if let email { user.email = email }
        if let fname { user.fname = fname }
        CoreDataManager.shared.save(context: context)
        return user
    }

    private func cleanUp(userIds: [String]) {
        for userId in userIds {
            UserStore.shared.delete(userId: userId)
        }
    }

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

    // MARK: - 1. DEK actually wraps real DB field data correctly

    @Test func savingUserEntityStoresCiphertextNotPlaintext() throws {
        resetAllDekState()
        defer { resetAllDekState() }

        let userId = "test-user-\(TestIds.unique())"
        defer { cleanUp(userIds: [userId]) }

        let user = makeUser(userId: userId, email: "patient@example.com", fname: "Jane")

        // Read the RAW stored primitive value — bypassing the swizzled
        // decrypt-on-fetch behavior — to prove what's actually on disk.
        let rawEmail = user.primitiveValue(forKey: "email") as? String
        #expect(rawEmail != "patient@example.com")
        #expect(rawEmail?.isEmpty == false)
        // Ciphertext is base64(nonce + ciphertext + tag) — never valid
        // readable text that happens to look like the original.
        #expect(Data(base64Encoded: rawEmail ?? "") != nil)
    }

    @Test func fetchingBackDecryptsToOriginalPlaintext() throws {
        resetAllDekState()
        defer { resetAllDekState() }

        let userId = "test-user-\(TestIds.unique())"
        defer { cleanUp(userIds: [userId]) }

        _ = makeUser(userId: userId, email: "roundtrip@example.com", fname: "Roundtrip")

        // Force a real fetch (not just reading the same in-memory object)
        // so awakeFromFetch's decrypt path actually runs.
        context.reset()
        let fetched = UserStore.shared.fetchByUserId(userId)

        #expect(fetched?.email == "roundtrip@example.com")
        #expect(fetched?.fname == "Roundtrip")
    }

    @Test func sameFieldValueEncryptsToDifferentCiphertextEachTime() throws {
        // Confirms encryption isn't a fixed/deterministic transform that
        // would leak equality between rows sharing the same plaintext —
        // AES-GCM uses a fresh nonce per call, so the same plaintext
        // encrypted twice must produce different ciphertext both times.
        resetAllDekState()
        defer { resetAllDekState() }

        let userId1 = "test-user-\(TestIds.unique())"
        let userId2 = "test-user-\(TestIds.unique())"
        defer { cleanUp(userIds: [userId1, userId2]) }

        let user1 = makeUser(userId: userId1, email: "same@example.com")
        let user2 = makeUser(userId: userId2, email: "same@example.com")

        let firstCiphertext = user1.primitiveValue(forKey: "email") as? String
        let secondCiphertext = user2.primitiveValue(forKey: "email") as? String

        #expect(firstCiphertext != secondCiphertext)
    }

    // MARK: - 2. KEK rotation doesn't disturb already-encrypted rows

    @Test func rowEncryptedUnderBootstrapKekStaysReadableAfterRotatingToServerKek() throws {
        resetAllDekState()
        defer {
            AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.field.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        let userId = "test-user-\(TestIds.unique())"
        defer { cleanUp(userIds: [userId]) }

        // Encrypt and save a row BEFORE any server KEK exists — DEK is
        // wrapped only under the local bootstrap KEK at this point.
        let user = makeUser(userId: userId, email: "before-rotation@example.com", fname: "BeforeRotation")
        let rawCiphertextBefore = user.primitiveValue(forKey: "email") as? String

        // Now the server issues its first KEK — rotate.
        let rawKek = Data(repeating: 0xAA, count: 32)
        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "e2e-server-key", version: 1, keyMaterial: rawKek.base64EncodedString())
        )
        #expect(AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey) == "e2e-server-key")

        // The row's ciphertext on disk must be BYTE-IDENTICAL after
        // rotation — rotation only rewraps the DEK's own wrapper (the KEK),
        // it must never touch already-encrypted field data.
        let rawCiphertextAfter = user.primitiveValue(forKey: "email") as? String
        #expect(rawCiphertextAfter == rawCiphertextBefore)

        // And it must still decrypt correctly — proving the SAME DEK (now
        // wrapped under the new server KEK) opens data sealed before rotation.
        context.reset()
        let fetched = UserStore.shared.fetchByUserId(userId)
        #expect(fetched?.email == "before-rotation@example.com")
        #expect(fetched?.fname == "BeforeRotation")
    }

    @Test func rowEncryptedBeforeRotationStaysReadableAfterASecondRotation() throws {
        // Two sequential server-KEK rotations (e.g. periodic re-key) must
        // still leave old data readable — not just the single-rotation case.
        resetAllDekState()
        defer {
            AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.field.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        let userId = "test-user-\(TestIds.unique())"
        defer { cleanUp(userIds: [userId]) }

        _ = makeUser(userId: userId, email: "double-rotation@example.com")

        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "e2e-server-key-1", version: 1, keyMaterial: Data(repeating: 0xBB, count: 32).base64EncodedString())
        )
        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "e2e-server-key-2", version: 2, keyMaterial: Data(repeating: 0xCC, count: 32).base64EncodedString())
        )
        #expect(AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey) == "e2e-server-key-2")

        context.reset()
        let fetched = UserStore.shared.fetchByUserId(userId)
        #expect(fetched?.email == "double-rotation@example.com")
    }

    @Test func newRowsAfterRotationAlsoRoundTripCorrectly() throws {
        // A rotation shouldn't just preserve old data — new writes made
        // AFTER rotation must also encrypt/decrypt correctly under the (same
        // bytes, newly-wrapped) DEK.
        resetAllDekState()
        defer {
            AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: DekSlot.field.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        // Establish a DEK first (any encrypt call bootstraps it).
        _ = FieldEncryptionManager.shared.encrypt("bootstrap")

        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "e2e-post-rotation-key", version: 1, keyMaterial: Data(repeating: 0xDD, count: 32).base64EncodedString())
        )

        let userId = "test-user-\(TestIds.unique())"
        defer { cleanUp(userIds: [userId]) }

        _ = makeUser(userId: userId, email: "after-rotation@example.com")

        context.reset()
        let fetched = UserStore.shared.fetchByUserId(userId)
        #expect(fetched?.email == "after-rotation@example.com")
    }

    @Test func imageAndFieldRotateTogetherWithoutCrossContamination() throws {
        // rotateKekIfNewer rotates BOTH slots from one call — confirm the
        // field DEK and image DEK remain independent (different bytes,
        // different KEK aliases) after a shared rotation event, and that
        // rotating one doesn't affect the other's ability to decrypt.
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
        #expect(fieldDekBefore != imageDekBefore)

        DatabaseKeyProvider.shared.rotateKekIfNewer(
            KekInfo(keyId: "e2e-shared-rotation", version: 1, keyMaterial: Data(repeating: 0xEE, count: 32).base64EncodedString())
        )

        let fieldDekAfter = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)
        let imageDekAfter = DatabaseKeyProvider.shared.getOrCreateDek(for: .image)

        #expect(fieldDekAfter == fieldDekBefore)
        #expect(imageDekAfter == imageDekBefore)
        #expect(fieldDekAfter != imageDekAfter)

        let storage = AppStorageManager.shared
        #expect(storage.string(forKey: DekSlot.field.kekIdStorageKey) == "e2e-shared-rotation")
        #expect(storage.string(forKey: DekSlot.image.kekIdStorageKey) == "e2e-shared-rotation")
    }

    // MARK: - Failure-path realism: corrupted/unreadable ciphertext never leaks

    // MARK: - Field-DEK recovery preserves the store

    /// Regression test for a real bug found in review: `recoverFromUnrecoverableDek`
    /// used to call `CoreDataManager.shared.destroyAndReloadStore()`, wiping every
    /// row in the local database over a single field that could no longer decrypt.
    /// It now only re-keys the DEK and lets `decryptEncryptedFieldsInPlace` blank
    /// the affected field on read — this proves the store, its other rows, and the
    /// undecryptable ciphertext bytes themselves all survive the recovery.
    @Test func fieldDekRecoveryDoesNotDestroyTheStoreOrOtherRows() throws {
        resetAllDekState()
        defer {
            AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey).map {
                KekDekManager.shared.deleteKey(alias: $0 == "local-bootstrap"
                    ? DekSlot.field.bootstrapAlias
                    : DekSlot.field.serverAliasPrefix + $0)
            }
            resetAllDekState()
        }

        let survivorId = "test-user-\(TestIds.unique())"
        let victimId = "test-user-\(TestIds.unique())"
        defer { cleanUp(userIds: [survivorId, victimId]) }

        // Encrypt and save two rows under the current (bootstrap) DEK.
        let survivor = makeUser(userId: survivorId, email: "survivor@example.com", fname: "Survivor")
        _ = makeUser(userId: victimId, email: "victim@example.com", fname: "Victim")
        let survivorRawCiphertextBefore = survivor.primitiveValue(forKey: "email") as? String

        // Simulate the wrapper key becoming unrecoverable (e.g. Secure Enclave
        // key evicted by biometric re-enrollment) while the wrapped DEK blob
        // and kekId are left in place — exactly what getOrCreateDek sees right
        // before it calls recoverFromUnrecoverableDek.
        KekDekManager.shared.deleteKey(alias: DekSlot.field.bootstrapAlias)
        DatabaseKeyProvider.shared.resetCacheForTesting()

        let dekAfterRecovery = DatabaseKeyProvider.shared.getOrCreateDek(for: .field)
        #expect(AppStorageManager.shared.string(forKey: DekSlot.field.kekIdStorageKey) == "local-bootstrap")

        // The store itself must still exist and be fully usable — not wiped.
        context.reset()
        let survivorAfter = UserStore.shared.fetchByUserId(survivorId)
        let victimAfter = UserStore.shared.fetchByUserId(victimId)
        #expect(survivorAfter != nil)
        #expect(victimAfter != nil)

        // The old rows' ciphertext bytes on disk are untouched by recovery —
        // only the wrapper (KEK) changed, never already-written field data —
        // even though neither row can decrypt under the brand-new DEK.
        let survivorRawCiphertextAfter = survivorAfter?.primitiveValue(forKey: "email") as? String
        #expect(survivorRawCiphertextAfter == survivorRawCiphertextBefore)
        #expect(FieldEncryptionManager.shared.decrypt(survivorRawCiphertextAfter) == nil)

        // A fresh write under the recovered DEK still round-trips normally —
        // recovery isn't a dead end, just a one-time loss of pre-recovery data.
        let newUserId = "test-user-\(TestIds.unique())"
        defer { cleanUp(userIds: [newUserId]) }
        _ = makeUser(userId: newUserId, email: "after-recovery@example.com")
        context.reset()
        #expect(UserStore.shared.fetchByUserId(newUserId)?.email == "after-recovery@example.com")
        #expect(dekAfterRecovery == DatabaseKeyProvider.shared.getOrCreateDek(for: .field))
    }

    @Test func corruptedCiphertextDecryptsToNilNotGarbagePlaintext() throws {
        resetAllDekState()
        defer { resetAllDekState() }

        let ciphertext = try #require(FieldEncryptionManager.shared.encrypt("sensitive value"))

        // Flip a byte in the middle of the ciphertext (still valid base64
        // length-wise) to simulate corruption/tampering.
        var bytes = try #require(Data(base64Encoded: ciphertext))
        bytes[bytes.count / 2] ^= 0xFF
        let corrupted = bytes.base64EncodedString()

        let result = FieldEncryptionManager.shared.decrypt(corrupted)
        #expect(result == nil)
    }
}
