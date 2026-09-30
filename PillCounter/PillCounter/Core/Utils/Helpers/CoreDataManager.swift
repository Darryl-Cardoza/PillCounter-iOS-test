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

    /// Shared by every instance: loading the model per container yields duplicate
    /// NSManagedObjectModels and "Failed to find a unique match for an NSEntityDescription".
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url)
        else {
            // Unrecoverable: every entity resolves through this model. Log, then fail fast.
            AppLogger.shared.error("CoreDataManager: failed to load Core Data model \(modelName) from bundle", event: .databaseError)
            fatalError("Failed to load Core Data model \(modelName)")
        }
        return model
    }()

    let container: NSPersistentContainer

    /// Production initializer — loads the on-disk, file-protected SQLite store.
    private init() {
        container = NSPersistentContainer(name: CoreDataManager.modelName, managedObjectModel: CoreDataManager.managedObjectModel)

        guard let description = container.persistentStoreDescriptions.first else {
            // Core Data seeds this at init; empty means it is broken.
            AppLogger.shared.error("CoreDataManager: persistentStoreDescriptions is empty, cannot configure store", event: .databaseError)
            fatalError("No store description")
        }

        // Encrypt at file level (iOS Data Protection)
        description.setOption(
            FileProtectionType.complete as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )

        // Existing on-disk stores must migrate on model changes or never load.
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        container.loadPersistentStores { description, error in
            if let error = error {
                // No store attached: later fetches would fail confusingly.
                assertionFailure("Failed to load Core Data: \(error)")
                AppLogger.shared.error("Failed to load Core Data", error: error, event: .databaseError)
            }
            #if DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                DBDebugLogger.printAll()
            }
            #endif
        }

        // Background contexts save to the coordinator, not through viewContext; this merges their changes in.
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Isolated in-memory store for unit tests.
    init(inMemory: Bool) {
        container = NSPersistentContainer(name: CoreDataManager.modelName, managedObjectModel: CoreDataManager.managedObjectModel)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                // Load failure here is a test-setup bug; fail fast.
                AppLogger.shared.error("CoreDataManager: failed to load in-memory Core Data store", error: error, event: .databaseError)
                fatalError("Failed to load in-memory Core Data: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    // core data context
    var context: NSManagedObjectContext {
        container.viewContext
    }
    
    var backgroundContext: NSManagedObjectContext {
        container.newBackgroundContext()
    }

    func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            AppLogger.shared.error("CoreData save error", error: error, event: .databaseError)
        }
    }

    /// Like `save(context:)`, but returns whether the save persisted (`true` if nothing to save).
    @discardableResult
    func saveReturningSuccess(context: NSManagedObjectContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            AppLogger.shared.error("CoreData save error", error: error, event: .databaseError)
            return false
        }
    }

    func resetContext() {
        container.viewContext.performAndWait {
            container.viewContext.reset()
        }
    }

    /// Deletes the on-disk store and reloads an empty one. Not called from production;
    /// only safe when nothing else is fetching/saving on this coordinator.
    func destroyAndReloadStore() {
        resetContext()

        for description in container.persistentStoreDescriptions {
            guard let url = description.url else { continue }
            do {
                try container.persistentStoreCoordinator.destroyPersistentStore(
                    at: url,
                    ofType: description.type,
                    options: nil
                )
            } catch {
                AppLogger.shared.error("CoreData destroyPersistentStore error", error: error, event: .databaseError)
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                AppLogger.shared.error("CoreData reload after destroy failed", error: error, event: .databaseError)
            }
        }
    }
}
