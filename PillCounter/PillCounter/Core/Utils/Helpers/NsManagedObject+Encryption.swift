//
//  level.swift
//  PillCounter
//
//  Created by Ritesh Parekh on 21/05/26.
//


//
//  NSManagedObject+Encryption.swift
//  PillCounter
//
//  Adds automatic field-level encryption to ALL Core Data entities
//  without subclassing or changing any existing code.
//
//  Works by swizzling NSManagedObject's willSave() and awakeFromFetch()
//  at the class level — every entity in the app gets encryption
//  for free just by adding this file.
//

import CoreData
import CryptoKit

// MARK: - Encrypted field registry

/// Central registry of which fields to encrypt per entity.
/// Key = entity name, Value = array of attribute names to encrypt.
private let encryptedFieldRegistry: [String: [String]] = [
    "UserEntity": [
        "email",
        "fname",
        "lname",
        "phone_number",
        "pharmacy_name",
        "npi_id",
        "avatar_url"
    ],
    "PillCountTransactionEntity": [
        "patient_name",
        "rx_no",
        "note"
    ],
    "PillCountTransactionDetailsEntity": [
        "image_path"
    ],
    "BatchCountEntity": [
        // No PII fields currently — add here if needed
    ],
    "DrugMasterEntity": [
        // NDC and drug_name are not PII — stored plaintext
    ],
    "BottleInfoEntity": [
        "lot_no",
        "serial_no"
    ]
    // FaceEmbeddingEntity.embedding intentionally NOT encrypted — field
    // encryption caused permanent decrypt failures whenever the Keychain
    // key was wiped/rotated (logout, fresh install), orphaning stored
    // embeddings. Store as plain base64 for now.
]

// MARK: - NSManagedObject extension

extension NSManagedObject {

    // MARK: - Swizzle on app start

    /// Call this once from AppDelegate or PillCounterApp.init()
    /// to install the encryption hooks on NSManagedObject.
    static func installEncryptionHooks() {
        swizzle(
            original: #selector(willSave),
            replacement: #selector(enc_willSave)
        )
        swizzle(
            original: #selector(awakeFromFetch),
            replacement: #selector(enc_awakeFromFetch)
        )
        swizzle(
            original: #selector(didSave),
            replacement: #selector(enc_didSave)
        )
    }

    // MARK: - Replacement implementations

    @objc private func enc_willSave() {
        // Call original willSave first
        enc_willSave()

        guard let entityName = entity.name,
              let fields = encryptedFieldRegistry[entityName],
              !fields.isEmpty
        else { return }

        let enc = FieldEncryptionManager.shared
        for field in fields {
            guard let plaintext = primitiveValue(forKey: field) as? String,
                  !plaintext.isEmpty,
                  !looksEncrypted(plaintext)
            else { continue }
            if let ciphertext = enc.encrypt(plaintext) {
                setPrimitiveValue(ciphertext, forKey: field)
            }
        }
    }

    @objc private func enc_awakeFromFetch() {
        // Call original awakeFromFetch first
        enc_awakeFromFetch()
        decryptEncryptedFieldsInPlace()
    }

    /// After a save, willSave() has encrypted the registered fields in memory.
    /// didSave() runs on the same object once the save completes, so we restore
    /// plaintext here — this keeps every registered in-memory object readable as
    /// plaintext regardless of which save path was used, fixing the ciphertext
    /// that previously surfaced when a saved object was read without re-fetching.
    @objc private func enc_didSave() {
        // Call original didSave first
        enc_didSave()

        // A deleted object's values must not be touched.
        guard !isDeleted else { return }
        decryptEncryptedFieldsInPlace()
    }

    // MARK: - Deterministic decryption

    /// Decrypts this object's registered encrypted fields in place, reading the
    /// raw stored value and writing back plaintext via `setPrimitiveValue`.
    ///
    /// Use this instead of `context.refresh(_, mergeChanges: false)` after a fetch:
    /// refaulting does NOT reliably re-run `awakeFromFetch` (a fault fulfilled from
    /// the row cache can return the ciphertext snapshot written by `willSave`),
    /// which is what leaked ciphertext into the UI. This call is deterministic and
    /// does not depend on fault-firing behavior.
    func decryptEncryptedFieldsInPlace() {
        guard let entityName = entity.name,
              let fields = encryptedFieldRegistry[entityName],
              !fields.isEmpty
        else { return }

        let enc = FieldEncryptionManager.shared
        for field in fields {
            guard let stored = primitiveValue(forKey: field) as? String,
                  !stored.isEmpty,
                  looksEncrypted(stored)
            else { continue }

            if let plaintext = enc.decrypt(stored) {
                if plaintext != stored {
                    setPrimitiveValue(plaintext, forKey: field)
                }
            } else {
                // decrypt() returned nil — `stored` is real ciphertext we cannot
                // open (key mismatch/unavailable/corruption). Never leave the
                // ciphertext in place where it could render in the UI; blank it.
                // The encrypted value on disk is untouched (setPrimitiveValue does
                // not mark the object dirty), so a later successful key load can
                // still decrypt it on the next fetch.
                setPrimitiveValue("", forKey: field)
            }
        }
    }

    // MARK: - Helpers

    /// Whether `value` is base64 that decodes to a genuine AES-GCM sealed
    /// box (nonce + ciphertext + 16-byte tag), NOT just "long enough base64."
    ///
    /// The previous version of this check only verified base64-validity and
    /// a >=28-byte length. That misclassified any sufficiently long
    /// plaintext base64 payload — e.g. a packed 128-float face embedding
    /// (~512 bytes decoded, ~684 chars base64) — as "encrypted," which meant
    /// `willSave` skipped encrypting it (guard already true) and every
    /// subsequent fetch's `decryptEncryptedFieldsInPlace()` tried to AES-GCM
    /// -open the plaintext bytes, failed, and blanked the field to "" (see
    /// below) — silently destroying the stored embedding on first read.
    /// Actually attempting the SealedBox parse (structural only, no key
    /// needed) is the only reliable way to tell "real ciphertext" from
    /// "plaintext that happens to be long base64."
    private func looksEncrypted(_ value: String) -> Bool {
        guard let data = Data(base64Encoded: value) else { return false }
        return (try? AES.GCM.SealedBox(combined: data)) != nil
    }

    // MARK: - Swizzle utility

    private static func swizzle(original: Selector, replacement: Selector) {
        guard
            let originalMethod  = class_getInstanceMethod(Self.self, original),
            let replacementMethod = class_getInstanceMethod(Self.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}