//
//  DatabaseKeyProvider.swift
//  PillCounter
//
//  DEK lifecycle for every AES key that protects locally-stored sensitive
//  data — this app has no SQLCipher-backed database, so unlike Android's
//  KEK/DEK design there is no single DB passphrase to protect. Instead each
//  sensitive-data consumer gets its own DEK:
//   • `.field`  — FieldEncryptionManager's key, for PII text columns in CoreData
//   • `.image`  — PhotoFileManager's key, for captured pill/bottle photos on disk
//
//  Each DEK is generated once and never changes except on hard recovery. It
//  is wrapped (AES-256-GCM, via `KekDekManager`) under a KEK: a device-local
//  bootstrap KEK until the server issues one via `/auth/me` (`kek` field),
//  after which rotation re-wraps every DEK under the new KEK in one pass and
//  discards the old one.
//

import CryptoKit
import Foundation

struct KekInfo {
    let keyId: String
    let version: Int
    let keyMaterial: String // base64-encoded raw AES-256 key bytes
}

/// One sensitive-data consumer's DEK identity: where its wrapped bytes and
/// KEK bookkeeping live, and (for pre-existing installs) where its key used
/// to be stored unwrapped, so migration doesn't orphan already-encrypted data.
struct DekSlot {
    let bootstrapAlias: String
    let serverAliasPrefix: String
    let wrappedStorageKey: String
    let kekIdStorageKey: String
    let kekVersionStorageKey: String
    let legacyRawKeyAccount: String
    let legacyRawKeyService: String?

    static let field = DekSlot(
        bootstrapAlias: "com.pillcounter.database.dek_bootstrap_kek",
        serverAliasPrefix: "com.pillcounter.database.server_kek_",
        wrappedStorageKey: AppStorageManager.AppStorageKeys.dekWrapped,
        kekIdStorageKey: AppStorageManager.AppStorageKeys.dekKekId,
        kekVersionStorageKey: AppStorageManager.AppStorageKeys.dekKekVersion,
        // Where FieldEncryptionManager's key lived before it was wrapped —
        // installs that already have a raw key here are migrated, not
        // regenerated, since it already encrypts live CoreData field data.
        legacyRawKeyAccount: "com.pillcounter.field.encryption.key.v1",
        legacyRawKeyService: Keychain.defaultService
    )

    static let image = DekSlot(
        bootstrapAlias: "com.pillcounter.image.dek_bootstrap_kek",
        serverAliasPrefix: "com.pillcounter.image.server_kek_",
        wrappedStorageKey: AppStorageManager.AppStorageKeys.imageDekWrapped,
        kekIdStorageKey: AppStorageManager.AppStorageKeys.imageDekKekId,
        kekVersionStorageKey: AppStorageManager.AppStorageKeys.imageDekKekVersion,
        // Where PhotoFileManager's key lived before it was wrapped — no
        // service attribute, matching the original KeychainHelper exactly.
        legacyRawKeyAccount: "com.pillcounter.imageEncryptionKey",
        legacyRawKeyService: nil
    )

    /// Every slot's bootstrap alias — the single source of truth
    /// `KekDekManager` uses to decide which aliases are Secure-Enclave-backed.
    /// Every new `DekSlot` must be added here or its bootstrap KEK silently
    /// falls back to the weaker Keychain-AES path.
    static var allBootstrapAliases: Set<String> {
        [field.bootstrapAlias, image.bootstrapAlias]
    }
}

final class DatabaseKeyProvider {

    static let shared = DatabaseKeyProvider()
    private init() {}

    private func alias(forKekId kekId: String, slot: DekSlot) -> String {
        kekId == "local-bootstrap" ? slot.bootstrapAlias : slot.serverAliasPrefix + kekId
    }

    private let lock = NSLock()

    /// In-memory cache of each unwrapped DEK, keyed by bootstrap alias
    /// (unique per slot). Consumers call `getOrCreateDek` on every
    /// encrypt/decrypt — every CRUD operation touching PII columns, every
    /// photo save/load — so unwrapping via Keychain/Secure Enclave on each
    /// call would put a hardware crypto round-trip on the hot path. A DEK
    /// only ever changes on rotation or recovery, both of which refresh
    /// this cache explicitly; everything else is served from memory.
    private var cachedDeks: [String: SymmetricKey] = [:]

    #if DEBUG
    /// Test-only: drops the in-memory DEK cache so a subsequent
    /// `getOrCreateDek()` re-derives from (test-controlled) Keychain/
    /// AppStorage state instead of returning a stale cached key.
    func resetCacheForTesting() {
        lock.lock()
        defer { lock.unlock() }
        cachedDeks.removeAll()
    }
    #endif

    /// Returns the DEK for `slot`, unwrapping the stored blob or
    /// bootstrapping a fresh DEK if none exists yet or the stored one can no
    /// longer be recovered. Cheap after the first call per slot — see
    /// `cachedDeks`.
    ///
    /// A recovery re-key (fresh DEK) invalidates every previously encrypted
    /// value under this slot — callers on that path must wipe/discard the
    /// affected local data, mirroring Android's "fresh DEK needs a fresh DB
    /// file" rule. See `recoverFromUnrecoverableDek`.
    @discardableResult
    func getOrCreateDek(for slot: DekSlot = .field) -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedDeks[slot.bootstrapAlias] {
            return cached
        }

        let storage = AppStorageManager.shared
        if let wrappedB64 = storage.string(forKey: slot.wrappedStorageKey),
           let kekId = storage.string(forKey: slot.kekIdStorageKey),
           let wrapped = Data(base64Encoded: wrappedB64) {
            do {
                let raw = try KekDekManager.shared.unwrap(alias: alias(forKekId: kekId, slot: slot), wrapped: wrapped)
                let dek = SymmetricKey(data: raw)
                cachedDeks[slot.bootstrapAlias] = dek
                return dek
            } catch {
                Log("❌ DatabaseKeyProvider: DEK unwrap failed for \(slot.bootstrapAlias) (\(error.localizedDescription)) — re-keying")
                return recoverFromUnrecoverableDek(slot: slot, storage: storage)
            }
        }

        if let legacyRaw = Keychain.data(account: slot.legacyRawKeyAccount, service: slot.legacyRawKeyService) {
            let dek = bootstrapWrapDek(raw: legacyRaw, slot: slot, storage: storage)
            // The raw key is now safely wrapped and persisted above — remove
            // the old plaintext copy so it doesn't linger in the Keychain
            // indefinitely as a second, unwrapped exposure of the same key.
            Keychain.deleteData(account: slot.legacyRawKeyAccount, service: slot.legacyRawKeyService)
            return dek
        }

        return generateAndBootstrapWrapDek(slot: slot, storage: storage)
    }

    private func generateAndBootstrapWrapDek(slot: DekSlot, storage: AppStorageManager) -> SymmetricKey {
        let dek = SymmetricKey(size: .bits256)
        let raw = dek.withUnsafeBytes { Data($0) }
        return bootstrapWrapDek(raw: raw, slot: slot, storage: storage)
    }

    /// Wraps `raw` (freshly generated, or an existing legacy key being
    /// migrated) under `slot`'s bootstrap KEK and persists it as the DEK.
    private func bootstrapWrapDek(raw: Data, slot: DekSlot, storage: AppStorageManager) -> SymmetricKey {
        let dek = SymmetricKey(data: raw)
        guard let wrapped = try? KekDekManager.shared.wrap(alias: slot.bootstrapAlias, plaintext: raw) else {
            Log("❌ DatabaseKeyProvider: failed to wrap freshly generated DEK for \(slot.bootstrapAlias) — returning unwrapped in-memory key")
            cachedDeks[slot.bootstrapAlias] = dek
            return dek
        }

        storage.setString(wrapped.base64EncodedString(), forKey: slot.wrappedStorageKey)
        storage.setString("local-bootstrap", forKey: slot.kekIdStorageKey)
        storage.setInt(0, forKey: slot.kekVersionStorageKey)
        cachedDeks[slot.bootstrapAlias] = dek
        return dek
    }

    /// The stored DEK could not be recovered — its wrapper key is gone or
    /// invalidated. Any value already encrypted under the old DEK is now
    /// permanently unreadable. Field DEK recovery destroys the local CoreData
    /// store (see `CoreDataManager.destroyAndReloadStore`); image DEK
    /// recovery only orphans existing encrypted photo files on disk — there
    /// is no bulk store to wipe, so old files are simply left undecryptable
    /// (matches `PhotoFileManager.loadDecryptedData`'s existing nil-on-failure
    /// behavior; no plaintext ever leaks).
    private func recoverFromUnrecoverableDek(slot: DekSlot, storage: AppStorageManager) -> SymmetricKey {
        storage.setString(nil, forKey: slot.wrappedStorageKey)
        storage.setString(nil, forKey: slot.kekIdStorageKey)
        storage.setInt(-1, forKey: slot.kekVersionStorageKey)
        if slot.bootstrapAlias == DekSlot.field.bootstrapAlias {
            CoreDataManager.shared.destroyAndReloadStore()
        }
        return generateAndBootstrapWrapDek(slot: slot, storage: storage)
    }

    /// Rewraps every known DEK (field + image) under a newly server-issued
    /// KEK, importing its raw key material into the Keychain once and
    /// reusing it for each slot. No-op if `kekInfo.version` is not newer
    /// than the version currently in effect for a given slot (safe to call
    /// on every `/auth/me` response, not just the first time a `kek`
    /// appears) — each slot tracks its own version, so if one slot somehow
    /// falls behind the other it still catches up independently.
    func rotateKekIfNewer(_ kekInfo: KekInfo) {
        rotateSlotIfNewer(.field, kekInfo)
        rotateSlotIfNewer(.image, kekInfo)
    }

    private func rotateSlotIfNewer(_ slot: DekSlot, _ kekInfo: KekInfo) {
        lock.lock()
        defer { lock.unlock() }

        let storage = AppStorageManager.shared
        let currentKekId = storage.string(forKey: slot.kekIdStorageKey)
        let currentVersion = storage.int(forKey: slot.kekVersionStorageKey)

        // Any server-issued KEK always supersedes the bootstrap KEK,
        // regardless of version number — the bootstrap KEK isn't part of
        // the server's version sequence, so comparing versions alone would
        // wrongly reject a legitimate first server KEK at version 0 (0 > 0
        // is false, yet 0 still needs to replace "local-bootstrap"). Once
        // already on a server KEK, only a strictly higher version rotates.
        let isFirstServerKek = currentKekId == nil || currentKekId == "local-bootstrap"
        guard isFirstServerKek || kekInfo.version > currentVersion else { return }

        guard let oldKekId = storage.string(forKey: slot.kekIdStorageKey),
              let oldWrappedB64 = storage.string(forKey: slot.wrappedStorageKey),
              let oldWrapped = Data(base64Encoded: oldWrappedB64) else {
            Log("❌ DatabaseKeyProvider: rotation requested but no existing wrapped DEK for \(slot.bootstrapAlias) — skipping")
            return
        }

        guard var rawKek = Data(base64Encoded: kekInfo.keyMaterial) else {
            Log("❌ DatabaseKeyProvider: rotation payload key_material is not valid base64 — skipping \(slot.bootstrapAlias), existing DEK left untouched")
            return
        }

        let newAlias = slot.serverAliasPrefix + kekInfo.keyId
        KekDekManager.shared.importKey(alias: newAlias, rawKeyBytes: rawKek)
        rawKek.resetBytes(in: 0..<rawKek.count)

        do {
            let dek = try KekDekManager.shared.unwrap(alias: alias(forKekId: oldKekId, slot: slot), wrapped: oldWrapped)
            let newWrapped = try KekDekManager.shared.wrap(alias: newAlias, plaintext: dek)

            storage.setString(newWrapped.base64EncodedString(), forKey: slot.wrappedStorageKey)
            storage.setString(kekInfo.keyId, forKey: slot.kekIdStorageKey)
            storage.setInt(kekInfo.version, forKey: slot.kekVersionStorageKey)
            // DEK bytes are unchanged by rotation — only the wrapper — so the
            // cache stays valid; refresh it anyway to avoid a redundant unwrap.
            cachedDeks[slot.bootstrapAlias] = SymmetricKey(data: dek)
        } catch {
            Log("❌ DatabaseKeyProvider: KEK rotation failed for \(slot.bootstrapAlias) (\(error.localizedDescription)) — rolling back imported key, existing DEK left untouched")
            KekDekManager.shared.deleteKey(alias: newAlias)
            return
        }

        KekDekManager.shared.deleteKey(alias: alias(forKekId: oldKekId, slot: slot))
    }
}
