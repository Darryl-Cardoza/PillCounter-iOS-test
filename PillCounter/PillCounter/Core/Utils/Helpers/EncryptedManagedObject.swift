//
//  for.swift
//  PillCounter
//
//  Created by Ritesh Parekh on 21/05/26.
//


//
//  EncryptedManagedObject.swift
//  PillCounter
//
//  A base class for NSManagedObject that automatically encrypts
//  sensitive string fields on write and decrypts on read.
//
//  HOW IT WORKS:
//  - Override `encryptedFields` in each entity subclass to declare
//    which string attributes contain sensitive data.
//  - willSave() intercepts every Core Data save and encrypts those fields.
//  - awakeFromFetch() and awakeFromInsert() decrypt them immediately
//    after loading so the rest of the app always sees plaintext.
//
//  NO OTHER CODE CHANGES NEEDED — ViewModels, LocalDataSources, and
//  Repositories all continue to read/write plain strings as before.
//  Encryption and decryption happen transparently inside Core Data's
//  own lifecycle hooks.
//

import CoreData

class EncryptedManagedObject: NSManagedObject {

    // MARK: - Override in subclasses

    /// Return the attribute names that contain sensitive data.
    /// These will be encrypted on save and decrypted on fetch.
    var encryptedFields: [String] { [] }

    // MARK: - Core Data lifecycle hooks

    /// Called before every save. Encrypts sensitive fields.
    override func willSave() {
        super.willSave()
        guard !encryptedFields.isEmpty else { return }

        for field in encryptedFields {
            guard let plaintext = value(forKey: field) as? String,
                  !plaintext.isEmpty,
                  !isEncrypted(plaintext)
            else { continue }

            // Encrypt and write back — setPrimitiveValue avoids
            // triggering another willSave call
            if let ciphertext = FieldEncryptionManager.shared.encrypt(plaintext) {
                setPrimitiveValue(ciphertext, forKey: field)
            }
        }
    }

    /// Called after fetching from the persistent store.
    /// Decrypts sensitive fields so the rest of the app sees plaintext.
    override func awakeFromFetch() {
        super.awakeFromFetch()
        decryptFields()
    }

    /// Called after an object is inserted into a context.
    override func awakeFromInsert() {
        super.awakeFromInsert()
        // No decryption needed on insert — fields start as plaintext
    }

    // MARK: - Private helpers

    private func decryptFields() {
        guard !encryptedFields.isEmpty else { return }
        for field in encryptedFields {
            guard let ciphertext = value(forKey: field) as? String,
                  !ciphertext.isEmpty,
                  isEncrypted(ciphertext)
            else { continue }

            if let plaintext = FieldEncryptionManager.shared.decrypt(ciphertext) {
                setPrimitiveValue(plaintext, forKey: field)
            }
        }
    }

    /// Heuristic to detect whether a string is already encrypted.
    /// AES-GCM ciphertext encoded as base64 is always longer than
    /// the minimum tag size (28 bytes base64 = 12 byte nonce + 16 byte tag).
    /// Plain strings rarely look like valid base64 of that structure.
    private func isEncrypted(_ value: String) -> Bool {
        guard value.count >= 28,
              let data = Data(base64Encoded: value),
              data.count >= 28
        else { return false }
        return true
    }
}