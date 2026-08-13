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

    // MARK: - Create

    /// Inserts a new active FaceUser. Caller is responsible for uniqueness
    /// checks (see `isNameTaken`) before calling this.
    @discardableResult
    func insertUser(id: String, name: String) -> FaceUserEntity {
        let entity = FaceUserEntity(context: context)
        entity.id = id
        entity.name = name
        entity.created_at = Date()
        entity.updated_at = Date()
        entity.is_active = true
        CoreDataManager.shared.save(context: context)
        return entity
    }

    // MARK: - Read

    func getUser(id: String) -> FaceUserEntity? {
        let request: NSFetchRequest<FaceUserEntity> = FaceUserEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func getAllUsers(activeOnly: Bool = true) -> [FaceUserEntity] {
        let request: NSFetchRequest<FaceUserEntity> = FaceUserEntity.fetchRequest()
        if activeOnly {
            request.predicate = NSPredicate(format: "is_active == YES")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Case-insensitive active-name check, used to reject duplicate enrollment names.
    func isNameTaken(_ name: String) -> Bool {
        let request: NSFetchRequest<FaceUserEntity> = FaceUserEntity.fetchRequest()
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

    func deleteUser(id: String) {
        guard let user = getUser(id: id) else { return }
        context.delete(user)
        CoreDataManager.shared.save(context: context)
    }

    /// Deletes every registered face user. Used when the field-encryption
    /// key is wiped/rotated (see AppStorageManager.clearKeychainOnFreshInstall)
    /// so no stale user rows are left pointing at now-undecryptable embeddings.
    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = FaceUserEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        } catch {
            Log("FaceUserStore: failed to delete all users")
        }
    }
}
