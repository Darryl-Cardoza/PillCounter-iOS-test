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

    /// Loaded exactly once per process and reused by EVERY `CoreDataManager`
    /// instance (`.shared` and every `init(inMemory:)`). `NSPersistentContainer
    /// (name:)` on its own resolves/loads the named `.xcdatamodeld` itself —
    /// calling it more than once in one process (e.g. `.shared` plus a
    /// test's own `CoreDataManager(inMemory: true)`) can produce two
    /// distinct `NSManagedObjectModel` instances for the same model name,
    /// and Core Data can then fail to bind a generated class (e.g.
    /// `UserEntity`) to a single unambiguous `NSEntityDescription` —
    /// surfacing as "+[UserEntity entity] Failed to find a unique match for
    /// an NSEntityDescription to a managed object subclass" the first time
    /// any entity of that type is touched, and breaking encryption's
    /// `entity.name` lookup (in `NsManagedObject+Encryption.swift`) silently
    /// for the remainder of the process. Sharing one model instance across
    /// every container avoids the ambiguity entirely.
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url)
        else {
            fatalError("Failed to load Core Data model \(modelName)")
        }
        return model
    }()

    let container: NSPersistentContainer

    /// Production initializer — loads the on-disk, file-protected SQLite store.
    private init() {
        container = NSPersistentContainer(name: CoreDataManager.modelName, managedObjectModel: CoreDataManager.managedObjectModel)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No store description")
        }

        // Encrypt at file level (iOS Data Protection)
        description.setOption(
            FileProtectionType.complete as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )

        // An existing on-disk store predating a model change (e.g. the
        // FaceUserEntity/FaceEmbeddingEntity additions) must migrate, or the
        // store never loads and every later fetch fails.
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        container.loadPersistentStores { description, error in
            if let error = error {
                // Continuing here leaves a container with no store attached —
                // every fetch afterwards fails in a way that reads like a
                // missing entity rather than a failed migration.
                assertionFailure("Failed to load Core Data: \(error)")
                print("Failed to load Core Data: \(error.localizedDescription)")
            }
            #if DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                DBDebugLogger.printAll()
            }
            #endif
        }

        // Background contexts (see `backgroundContext` below) save directly to
        // the persistent store coordinator, as siblings of `viewContext`, not
        // as its children — a background save only reaches `viewContext` via
        // this merge notification. Without it, `viewContext` keeps serving
        // stale snapshots (e.g. `is_synced`) and stale references to objects
        // a background context deleted.
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// In-memory initializer for unit tests. Each instance gets an isolated
    /// store that never touches disk, so tests can build and query entities
    /// without affecting the app database or each other. Shares the same
    /// cached `managedObjectModel` as `.shared` — see that property's doc
    /// comment for why that matters.
    ///
    /// Usage in a test:
    /// ```
    /// let cd = CoreDataManager(inMemory: true)
    /// let txn = PillCountTransactionEntity(context: cd.context)
    /// ```
    init(inMemory: Bool) {
        container = NSPersistentContainer(name: CoreDataManager.modelName, managedObjectModel: CoreDataManager.managedObjectModel)

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
            Log("❌ CoreData save error: \(error.localizedDescription)")
        }
    }

    func resetContext() {
        container.viewContext.performAndWait {
            container.viewContext.reset()
        }
    }

    /// Destroys every persistent store file backing this container and
    /// reloads a fresh, empty one at the same URL. Unlike `resetContext()`
    /// (which only clears the in-memory context), this actually deletes the
    /// on-disk data — used when the field-encryption DEK is unrecoverable,
    /// so existing rows contain permanently undecryptable ciphertext.
    ///
    /// Only safe to call when nothing else is actively fetching/saving on
    /// this coordinator — `destroyPersistentStore` is not documented as safe
    /// concurrent with in-flight context operations, and any `NSManagedObject`
    /// already faulted from the destroyed store becomes invalid afterward.
    /// This is an accepted, narrow risk: the call site (an unrecoverable-DEK
    /// recovery) is expected to be exceedingly rare — normally only right
    /// after a corrupted/invalidated Keychain item — not a routine path.
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
                Log("❌ CoreData destroyPersistentStore error: \(error.localizedDescription)")
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                Log("❌ CoreData reload after destroy failed: \(error.localizedDescription)")
            }
        }
    }
}
