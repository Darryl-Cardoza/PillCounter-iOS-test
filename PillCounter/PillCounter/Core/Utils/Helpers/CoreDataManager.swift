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

    let container: NSPersistentContainer

    // init function
    private init() {
        container = NSPersistentContainer(name: "PillCounter")

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

    private static let modelName = "PillCounter"
}
