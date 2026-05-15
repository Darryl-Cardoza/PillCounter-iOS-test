//
//  CoreDataManager.swift
//  PillCounter
//

import CoreData

final class CoreDataManager {

    static let shared = CoreDataManager()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "PillCounter")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store description found")
        }

        migrateUnencryptedStoreIfNeeded(description: description)

        let passphrase = DatabaseKeyManager.getOrCreatePassphrase()
        description.setOption(passphrase as NSObject, forKey: "passphrase")

        description.setOption(
            FileProtectionType.completeUnlessOpen as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )

        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        description.setOption(true as NSNumber,
                              forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber,
                              forKey: NSInferMappingModelAutomaticallyOption)

        container.loadPersistentStores { _, error in
            if let error = error {
                Log("CoreData failed to load: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Contexts

    var context: NSManagedObjectContext { container.viewContext }

    var backgroundContext: NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }

    // MARK: - Save

    func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Log("Core Data save error: \(error.localizedDescription)")
        }
    }

    // MARK: - Reset

    func resetContext() {
        container.viewContext.performAndWait {
            container.viewContext.reset()
        }
    }
}

// MARK: - One-time plaintext → SQLCipher migration

private extension CoreDataManager {

    func migrateUnencryptedStoreIfNeeded(description: NSPersistentStoreDescription) {
        guard let storeURL = description.url,
              FileManager.default.fileExists(atPath: storeURL.path)
        else { return }

        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let isPlaintext = sqlite3_prepare_v2(
            db, "SELECT count(*) FROM sqlite_master;", -1, &stmt, nil
        ) == SQLITE_OK
        sqlite3_finalize(stmt)
        guard isPlaintext else { return }

        Log("⚠️  Unencrypted CoreData store detected — migrating to SQLCipher…")

        let passphrase    = DatabaseKeyManager.getOrCreatePassphrase()
        let escapedKey    = passphrase.replacingOccurrences(of: "'", with: "''")
        let tempURL       = storeURL.deletingLastPathComponent()
            .appendingPathComponent("PillCounter_enc.sqlite")

        sqlite3_exec(db,
            "ATTACH DATABASE '\(tempURL.path)' AS encrypted KEY '\(escapedKey)';",
            nil, nil, nil)
        sqlite3_exec(db, "SELECT sqlcipher_export('encrypted');", nil, nil, nil)
        sqlite3_exec(db, "DETACH DATABASE encrypted;", nil, nil, nil)
        sqlite3_close(db)

        // Swap encrypted file over the plaintext one.
        let fm = FileManager.default
        do {
            for suffix in ["", "-wal", "-shm"] {
                let old = suffix.isEmpty ? storeURL
                    : storeURL.appendingPathExtension(suffix)
                let new = suffix.isEmpty ? tempURL
                    : tempURL.appendingPathExtension(suffix)
                if fm.fileExists(atPath: old.path) { try fm.removeItem(at: old) }
                if fm.fileExists(atPath: new.path) { try fm.moveItem(at: new, to: old) }
            }
            Log("✅ CoreData store migrated to SQLCipher.")
        } catch {
            Log("❌ Migration swap failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - SQLite C bridge (resolved by SQLCipher linker flags)

@_silgen_name("sqlite3_open")
private func sqlite3_open(
    _ filename: UnsafePointer<CChar>?,
    _ ppDb: UnsafeMutablePointer<OpaquePointer?>?
) -> Int32

@_silgen_name("sqlite3_close")
private func sqlite3_close(_ db: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_exec")
private func sqlite3_exec(
    _ db: OpaquePointer?,
    _ sql: UnsafePointer<CChar>?,
    _ callback: (@convention(c) (UnsafeMutableRawPointer?, Int32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32)?,
    _ arg: UnsafeMutableRawPointer?,
    _ errmsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

@_silgen_name("sqlite3_prepare_v2")
private func sqlite3_prepare_v2(
    _ db: OpaquePointer?,
    _ zSql: UnsafePointer<CChar>?,
    _ nByte: Int32,
    _ ppStmt: UnsafeMutablePointer<OpaquePointer?>?,
    _ pzTail: UnsafeMutablePointer<UnsafePointer<CChar>?>?
) -> Int32

@_silgen_name("sqlite3_finalize")
private func sqlite3_finalize(_ pStmt: OpaquePointer?) -> Int32

private let SQLITE_OK: Int32 = 0

