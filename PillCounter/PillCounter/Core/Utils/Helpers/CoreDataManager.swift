//
//  CoreDataManager.swift
//  PillCounter
//
//  REQUIRED: PillCounter-Bridging-Header.h must contain:
//    #import <SQLCipher/sqlite3.h>
//
//  Uses NSPersistentStoreCoordinator directly instead of NSPersistentContainer
//  to guarantee SQLCipher keys the file before Core Data opens it.
//

import CoreData

final class CoreDataManager {

    static let shared = CoreDataManager()

    // MARK: - Public interface

    let container: NSPersistentContainer

    var context: NSManagedObjectContext { container.viewContext }

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

    // MARK: - Constants

    private static let modelName      = "PillCounter"
    private static let storeFileName  = "PillCounter_enc.sqlite"
    private static let legacyFileName = "PillCounter.sqlite"

    // MARK: - Init

    private init() {
        // ── 1. Load model ──────────────────────────────────────────────────
        guard
            let modelURL = Bundle.main.url(
                forResource: Self.modelName, withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: modelURL)
        else {
            fatalError("CoreDataManager: \(Self.modelName).momd not found in bundle")
        }

        // ── 2. Store URL ───────────────────────────────────────────────────
        let storeURL = NSPersistentContainer
            .defaultDirectoryURL()
            .appendingPathComponent(Self.storeFileName)

        // ── 3. Passphrase ──────────────────────────────────────────────────
        let passphrase = DatabaseKeyManager.getOrCreatePassphrase()

        // ── 4. Legacy migration (static — no self needed) ──────────────────
        Self.migrateUnencryptedStoreIfNeeded(
            encryptedStoreURL: storeURL,
            passphrase: passphrase
        )

        // ── 5. Register key with SQLCipher before addPersistentStore ────────
        Self.applyKey(to: storeURL, passphrase: passphrase)

        // ── 6. Add store via coordinator ───────────────────────────────────
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSPersistentHistoryTrackingKey: true,
            NSPersistentStoreFileProtectionKey: FileProtectionType.completeUnlessOpen
        ]

        do {
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: options
            )
            Log("✅ CoreData: encrypted store loaded")
        } catch {
            Log("❌ CoreData: addPersistentStore failed: \(error)")
        }

        // ── 7. Build container backed by our coordinator ───────────────────
        let persistentContainer = NSPersistentContainer(
            name: Self.modelName,
            managedObjectModel: model
        )

        // Remove the default empty store descriptions so the container
        // uses our already-open coordinator instead of creating its own.
        persistentContainer.persistentStoreDescriptions = []

        // Attach our coordinator's store to the container's coordinator
        // by removing the container's default stores and re-adding ours.
        for store in persistentContainer.persistentStoreCoordinator.persistentStores {
            try? persistentContainer.persistentStoreCoordinator.remove(store)
        }

        do {
            try persistentContainer.persistentStoreCoordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: options
            )
        } catch {
            Log("❌ CoreData: container coordinator setup failed: \(error)")
        }

        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true

        // ── 8. Assign — all stored properties now initialized ──────────────
        container = persistentContainer
    }
}

// MARK: - Static helpers (called from init before self is available)

private extension CoreDataManager {

    /// Registers the SQLCipher key for storeURL. Must be called before
    /// addPersistentStore so SQLCipher's sqlite3_open replacement can
    /// apply it when Core Data opens the file.
    static func applyKey(to storeURL: URL, passphrase: String) {
        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else {
            Log("❌ applyKey: sqlite3_open failed")
            return
        }
        defer { sqlite3_close(db) }

        let result = passphrase.withCString { ptr -> Int32 in
            sqlite3_key(db, ptr, Int32(passphrase.utf8.count))
        }

        if result == SQLITE_OK {
            Log("✅ applyKey: key registered for \(storeURL.lastPathComponent)")
        } else {
            Log("❌ applyKey: sqlite3_key failed with code \(result)")
        }
    }

    /// Migrates a legacy plaintext PillCounter.sqlite into the new
    /// encrypted store file. Runs once, exits immediately on all
    /// subsequent launches once the plaintext file is removed.
    static func migrateUnencryptedStoreIfNeeded(
        encryptedStoreURL: URL,
        passphrase: String
    ) {
        let storeDir     = NSPersistentContainer.defaultDirectoryURL()
        let plaintextURL = storeDir.appendingPathComponent(legacyFileName)

        guard FileManager.default.fileExists(atPath: plaintextURL.path) else { return }
        guard isPlaintext(plaintextURL) else {
            removeStoreFiles(baseURL: plaintextURL)
            return
        }

        Log("⚠️ Legacy plaintext store found — migrating…")

        var srcDb: OpaquePointer?
        guard sqlite3_open(plaintextURL.path, &srcDb) == SQLITE_OK else { return }
        defer { sqlite3_close(srcDb) }

        let safePass = passphrase.replacingOccurrences(of: "'", with: "''")
        guard sqlite3_exec(
            srcDb,
            "ATTACH DATABASE '\(encryptedStoreURL.path)' AS encrypted KEY '\(safePass)';",
            nil, nil, nil
        ) == SQLITE_OK else { return }

        sqlite3_exec(srcDb, "SELECT sqlcipher_export('encrypted');", nil, nil, nil)
        sqlite3_exec(srcDb, "DETACH DATABASE encrypted;", nil, nil, nil)

        removeStoreFiles(baseURL: plaintextURL)
        Log("✅ Legacy migration complete")
    }

    static func isPlaintext(_ url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let ok = sqlite3_prepare_v2(
            db, "SELECT count(*) FROM sqlite_master;", -1, &stmt, nil
        ) == SQLITE_OK
        sqlite3_finalize(stmt)
        return ok
    }

    static func removeStoreFiles(baseURL: URL) {
        let base = baseURL.path
        for path in [base, "\(base)-wal", "\(base)-shm"] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try? FileManager.default.removeItem(atPath: path)
            Log("🗑 Removed \((path as NSString).lastPathComponent)")
        }
    }
}
