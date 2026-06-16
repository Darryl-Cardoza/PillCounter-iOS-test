//
//  CoreDataManager.swift
//  PillCounter
//
//  Standard NSPersistentContainer — no SQLCipher dependency.
//  Data is encrypted at the field level by FieldEncryptionManager
//  before being written to SQLite.
//
//  The SQLite file is plaintext but every sensitive field value is
//  AES-256-GCM encrypted — an attacker who extracts the database
//  sees only ciphertext. The decryption key lives in the Keychain
//  with kSecAttrAccessibleWhenUnlockedThisDeviceOnly.
//

import CoreData

final class CoreDataManager {

    static let shared = CoreDataManager()

    private static let modelName = "PillCounter"

    let container: NSPersistentContainer

    /// Production initializer — loads the on-disk, file-protected SQLite store.
    private init() {
        container = NSPersistentContainer(name: CoreDataManager.modelName)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No store description")
        }

        // Encrypt at file level (iOS Data Protection)
        description.setOption(
            FileProtectionType.complete as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )

        container.loadPersistentStores { description, error in
            if let error = error {
                print("Failed to load Core Data: \(error.localizedDescription)")
            }
            #if DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                DBDebugLogger.printAll()
            }
            #endif
        }
    }

    /// In-memory initializer for unit tests. Each instance gets an isolated
    /// store that never touches disk, so tests can build and query entities
    /// without affecting the app database or each other.
    ///
    /// Usage in a test:
    /// ```
    /// let cd = CoreDataManager(inMemory: true)
    /// let txn = PillCountTransactionEntity(context: cd.context)
    /// ```
    init(inMemory: Bool) {
        container = NSPersistentContainer(name: CoreDataManager.modelName)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load in-memory Core Data: \(error.localizedDescription)")
            }
        }
    }
    
    // core data context
    var context: NSManagedObjectContext {
        container.viewContext
    }
    
    var backgroundContext: NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }

    func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Log("❌ CoreData save error: \(error.localizedDescription)")
        }
    }

    func resetContext() {
        container.viewContext.performAndWait {
            container.viewContext.reset()
        }
    }
}
