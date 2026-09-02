//
//  UserDAO.swift
//  PillCounter
//

import CoreData

final class UserStore {

    enum UserField: String {
        case fname         = "fname"
        case lname         = "lname"
        case email         = "email"
        case phoneNumber   = "phone_number"
        case avatarUrl     = "avatar_url"
        case isProfileCompleted = "is_profile_completed"
        case pharmacyName  = "pharmacy_name"
        case npiId         = "npi_id"
        case language      = "language"
        case timezone      = "timezone"
        case notifications = "notifications"
        case isVerified    = "is_verified"
        case createdAt     = "created_at"
    }

    static let shared = UserStore()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    // MARK: - Upsert

    /// Creates a new UserEntity or updates the existing one for the same user_id.
    /// Existing transactions are preserved — only profile fields are refreshed.
    func save(from response: UserResponse) {
        guard let userDetails = response.data,
              let userId = userDetails.profile?.userId, !userId.isEmpty else { return }

        let isNew = fetchByUserId(userId) == nil
        let entity = fetchByUserId(userId) ?? UserEntity(context: context)

        if isNew {
            entity.user_id = userId
            entity.created_at = Date()
        }

        if let profile = userDetails.profile {
            entity.fname = profile.fname
            entity.lname = profile.lname
            entity.email = profile.email ?? ""
            entity.phone_number = profile.phoneNumber ?? ""
            entity.avatar_url = profile.avatarURL ?? ""
            entity.is_profile_completed = profile.isProfileCompleted ?? false
            entity.pharmacy_name = profile.pharmacyName ?? ""
            entity.npi_id = profile.npiID ?? ""
            entity.is_verified = profile.isVerified ?? false
        }
        if let settings = userDetails.settings {
            entity.notifications = settings.notificationsEnabled ?? false
            entity.language = settings.language ?? "en"
            entity.timezone = settings.timezone ?? "Asia/Kolkata"
        }

        CoreDataManager.shared.save(context: context)
        // didSave restores plaintext in memory (see NSManagedObject+Encryption),
        // so reading entity fields below / by callers without re-fetching is safe.
        let action = isNew ? "CREATED" : "UPDATED"
        print("👤 [UserDAO] \(action) — userId: \(userId), email: \(entity.email ?? "-"), name: \((entity.fname ?? "") + " " + (entity.lname ?? ""))")
    }

    // MARK: - Read

    func fetchByUserId(_ userId: String) -> UserEntity? {
        let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user_id == %@", userId)
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        result.decryptEncryptedFieldsInPlace()
        return result
    }

    /// Same as `fetchByUserId(_:)`, but fetches via an explicit context —
    /// see `TransactionStore.fetchById(_:in:)`. This store has no `sync`
    /// helper of its own; `performAndWait` is added explicitly here since
    /// this overload is for callers on a different queue than `viewContext`.
    func fetchByUserId(_ userId: String, in context: NSManagedObjectContext) -> UserEntity? {
        context.performAndWait {
            let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
            request.predicate = NSPredicate(format: "user_id == %@", userId)
            request.fetchLimit = 1
            guard let result = try? context.fetch(request).first else { return nil }
            result.decryptEncryptedFieldsInPlace()
            return result
        }
    }

    func fetchAll() -> [UserEntity] {
        let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
        let results = (try? context.fetch(request)) ?? []
        results.forEach { $0.decryptEncryptedFieldsInPlace() }
        return results
    }

    func fetchTransactionsByDateRange(
        for user: UserEntity,
        startDateTs: Int64,
        endDateTs: Int64
    ) -> [PillCountTransactionEntity] {
        let set = user.transactions as? Set<PillCountTransactionEntity> ?? []
        return set
            .filter { $0.created_at >= startDateTs && $0.created_at < endDateTs && !$0.is_deleted }
            .sorted { $0.created_at < $1.created_at }
    }

    // MARK: - Update

    func update(userId: String, field: UserField, value: Any?) {
        guard let user = fetchByUserId(userId) else { return }
        user.setValue(value, forKey: field.rawValue)
        CoreDataManager.shared.save(context: context)
        print("👤 [UserDAO] UPDATED — userId: \(userId), field: \(field.rawValue), value: \(value ?? "nil")")
    }

    func updateField(_ field: String, value: Any, for userId: String) {
        guard let user = fetchByUserId(userId) else { return }
        user.setValue(value, forKey: field)
        CoreDataManager.shared.save(context: context)
        print("👤 [UserDAO] UPDATED field — userId: \(userId), field: \(field), value: \(value)")
    }

    // MARK: - Delete

    func delete(userId: String) {
        guard let user = fetchByUserId(userId) else { return }
        context.delete(user)
        CoreDataManager.shared.save(context: context)
        print("👤 [UserDAO] DELETED — userId: \(userId)")
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = UserEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            print("👤 [UserDAO] DELETED ALL — all user records removed")
        } catch {
            print("Failed to delete all")
        }
    }
}
