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
        "lot_no",
        "note",
        "barcode_image"
    ],
    "PillCountTransactionDetailsEntity": [
        "image_path"
    ],
    "BatchCountEntity": [
        // No PII fields currently — add here if needed
    ],
    "DrugMasterEntity": [
        // NDC and drug_name are not PII — stored plaintext
    ]
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

        guard let entityName = entity.name,
              let fields = encryptedFieldRegistry[entityName],
              !fields.isEmpty
        else { return }

        let enc = FieldEncryptionManager.shared
        for field in fields {
            guard let ciphertext = primitiveValue(forKey: field) as? String,
                  !ciphertext.isEmpty,
                  looksEncrypted(ciphertext)
            else { continue }
            if let plaintext = enc.decrypt(ciphertext) {
                setPrimitiveValue(plaintext, forKey: field)
            }
        }
    }

    // MARK: - Helpers

    private func looksEncrypted(_ value: String) -> Bool {
        guard value.count >= 28,
              let data = Data(base64Encoded: value),
              data.count >= 28
        else { return false }
        return true
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