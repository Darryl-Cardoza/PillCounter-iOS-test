//
//  FaceEmbeddingStore.swift
//  PillCounter
//

import CoreData

/// DAO for FaceEmbeddingEntity. `embedding` is stored as a base64 string
/// (packed Float32 bytes) so it flows through the existing field-encryption
/// hook (NSManagedObject+Encryption) exactly like any other String field —
/// never logged, never touched in memory outside this store + the caller
/// that packs/unpacks it.
final class FaceEmbeddingStore {

    static let shared = FaceEmbeddingStore()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    /// Entity name spelled out instead of going through the generated
    /// `FaceEmbeddingEntity.fetchRequest()`. That generated helper resolves the
    /// entity via `+[NSManagedObject entity]`, which returns nil (and builds a
    /// request with an empty entity name) if it runs before the model is
    /// loaded — Core Data then throws NSInternalInconsistencyException.
    private static let entityName = "FaceEmbeddingEntity"

    private func makeDeleteRequest() -> NSFetchRequest<NSFetchRequestResult> {
        NSFetchRequest<NSFetchRequestResult>(entityName: FaceEmbeddingStore.entityName)
    }

    private func makeFetchRequest() -> NSFetchRequest<FaceEmbeddingEntity> {
        NSFetchRequest<FaceEmbeddingEntity>(entityName: FaceEmbeddingStore.entityName)
    }

    // MARK: - Create

    @discardableResult
    func insertEmbedding(
        id: String,
        userId: String,
        embeddingBase64: String,
        qualityScore: Float
    ) -> FaceEmbeddingEntity {
        let entity = FaceEmbeddingEntity(context: context)
        entity.id = id
        entity.user_id = userId
        entity.embedding = embeddingBase64
        entity.quality_score = qualityScore
        entity.created_at = Date()
        CoreDataManager.shared.save(context: context)
        return entity
    }

    // MARK: - Read

    func getEmbeddingsForUser(userId: String) -> [FaceEmbeddingEntity] {
        let request = makeFetchRequest()
        request.predicate = NSPredicate(format: "user_id == %@", userId)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        let results = (try? context.fetch(request)) ?? []
        // Refaulting a row from Core Data's row cache does not reliably
        // re-run awakeFromFetch (see NSManagedObject+Encryption.swift), so a
        // fetch can return the still-encrypted ciphertext string instead of
        // the plaintext base64 payload. Decrypt deterministically here —
        // matches UserStore's fetch methods, which do the same.
        results.forEach { $0.decryptEncryptedFieldsInPlace() }
        return results
    }

    func getAllEmbeddings() -> [FaceEmbeddingEntity] {
        let request = makeFetchRequest()
        let results = (try? context.fetch(request)) ?? []
        results.forEach { $0.decryptEncryptedFieldsInPlace() }
        return results
    }

    // MARK: - Delete

    func deleteEmbeddingsForUser(userId: String) {
        let request = makeDeleteRequest()
        request.predicate = NSPredicate(format: "user_id == %@", userId)
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        } catch {
            Log("FaceEmbeddingStore: failed to delete embeddings for user \(userId)")
        }
    }

    /// Deletes every stored embedding row. Used when the field-encryption
    /// key is wiped/rotated (see AppStorageManager.clearKeychainOnFreshInstall)
    /// so no ciphertext is left behind that the new key can never open.
    func deleteAll() {
        let request = makeDeleteRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        } catch {
            Log("FaceEmbeddingStore: failed to delete all embeddings")
        }
    }
}
