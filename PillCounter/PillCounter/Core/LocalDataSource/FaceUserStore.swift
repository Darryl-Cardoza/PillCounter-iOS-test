//
//  FaceUserStore.swift
//  PillCounter
//

import CoreData

/// DAO for FaceUserEntity. Same shape as UserStore — singleton wrapping
/// CoreDataManager.shared, no DI seam (matches the rest of Core/LocalDataSource).
final class FaceUserStore {

    static let shared = FaceUserStore()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    /// Entity name spelled out instead of going through the generated
    /// `FaceUserEntity.fetchRequest()` — see the same note in
    /// FaceEmbeddingStore: the generated helper resolves the entity via
    /// `+[NSManagedObject entity]`, which yields an empty entity name if it
    /// runs before the managed object model is loaded.
    private static let entityName = "FaceUserEntity"

    private func makeDeleteRequest() -> NSFetchRequest<NSFetchRequestResult> {
        NSFetchRequest<NSFetchRequestResult>(entityName: FaceUserStore.entityName)
    }

    private func makeFetchRequest() -> NSFetchRequest<FaceUserEntity> {
        NSFetchRequest<FaceUserEntity>(entityName: FaceUserStore.entityName)
    }

    // MARK: - Create

    /// Inserts a new active FaceUser. Caller is responsible for uniqueness
    /// checks (see `isNameTaken`) before calling this. `name` stays the
    /// combined "First Last" display value that the rest of Core (embedding
    /// lookups, authentication welcome text) already reads.
    @discardableResult
    func insertUser(id: String, firstName: String, lastName: String) -> FaceUserEntity {
        let entity = FaceUserEntity(context: context)
        entity.id = id
        entity.first_name = firstName
        entity.last_name = lastName
        entity.name = "\(firstName) \(lastName)"
        entity.created_at = Date()
        entity.updated_at = Date()
        entity.is_active = true
        CoreDataManager.shared.save(context: context)
        return entity
    }

    // MARK: - Read

    func getUser(id: String) -> FaceUserEntity? {
        let request = makeFetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        let result = try? context.fetch(request).first
        // `photo_path` is a registered encrypted field, and a refaulted object
        // can hand back the ciphertext snapshot willSave wrote rather than
        // re-running awakeFromFetch — decrypt deterministically instead (same
        // reasoning as UserStore/FaceEmbeddingStore).
        result?.decryptEncryptedFieldsInPlace()
        return result
    }

    func getAllUsers(activeOnly: Bool = true) -> [FaceUserEntity] {
        let request = makeFetchRequest()
        if activeOnly {
            request.predicate = NSPredicate(format: "is_active == YES")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        let results = (try? context.fetch(request)) ?? []
        results.forEach { $0.decryptEncryptedFieldsInPlace() }
        return results
    }

    /// Case-insensitive active-name check, used to reject duplicate enrollment names.
    func isNameTaken(_ name: String) -> Bool {
        let request = makeFetchRequest()
        request.predicate = NSPredicate(
            format: "is_active == YES AND name ==[c] %@", name
        )
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    // MARK: - Update / Delete

    func deactivateUser(id: String) {
        guard let user = getUser(id: id) else { return }
        user.is_active = false
        user.updated_at = Date()
        CoreDataManager.shared.save(context: context)
    }

    func activateUser(id: String) {
        guard let user = getUser(id: id) else { return }
        user.is_active = true
        user.updated_at = Date()
        CoreDataManager.shared.save(context: context)
    }

    /// Stamps the user as the current session owner. Called on every
    /// successful face match (session unlock), independent of `updated_at`
    /// which tracks record edits (name/active-state changes), not usage.
    func updateLastAuthenticatedAt(id: String, date: Date = Date()) {
        guard let user = getUser(id: id) else { return }
        user.last_authenticated_at = date
        CoreDataManager.shared.save(context: context)
    }

    /// Points the user row at its stored enrollment avatar. `filename` is the
    /// bare filename inside FaceAvatarStore's directory, never an absolute
    /// path — container paths change across reinstall and restore.
    func setPhotoPath(id: String, filename: String?) {
        guard let user = getUser(id: id) else { return }
        user.photo_path = filename
        user.updated_at = Date()
        CoreDataManager.shared.save(context: context)
    }

    func deleteUser(id: String) {
        guard let user = getUser(id: id) else { return }
        // The avatar file has no owner once this row is gone, so it must go
        // with it — read the filename before the object is deleted.
        FaceAvatarStore.shared.delete(filename: user.photo_path)
        context.delete(user)
        CoreDataManager.shared.save(context: context)
    }

    /// Deletes every registered face user. Used when the field-encryption
    /// key is wiped/rotated (see AppStorageManager.clearKeychainOnFreshInstall)
    /// so no stale user rows are left pointing at now-undecryptable embeddings.
    func deleteAll() {
        let request = makeDeleteRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        } catch {
            Log("FaceUserStore: failed to delete all users")
        }
        // A batch delete bypasses `deleteUser`, so no per-row avatar cleanup
        // ran — clear the whole avatar directory instead.
        FaceAvatarStore.shared.deleteAll()
    }
}
