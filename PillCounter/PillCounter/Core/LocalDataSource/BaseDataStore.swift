//
//  BaseDataStore.swift
//  PillCounter
//
//  Shared Core Data fetch/pagination/context-confinement plumbing used by
//  every concrete store (TransactionStore, BatchStore, TransactionDetailStore,
//  StockTxnStore). Each store subclasses this for the mechanical parts —
//  building the entity-specific NSPredicate/NSSortDescriptor stays in the
//  subclass, since predicates differ enough between stores (field names,
//  whether is_deleted is baked into an id lookup, etc.) that a fully generic
//  predicate builder isn't worth the indirection.
//

import CoreData

class BaseDataStore<Entity: NSManagedObject> {

    var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    /// Confines every Core Data touch to `context`'s owning queue (the main
    /// queue for `viewContext`). Background callers — HL7 sync queues, the
    /// image web server — call into stores from their own DispatchQueue with
    /// no hop otherwise. `performAndWait` is safe to call re-entrantly when
    /// already on the right queue (runs the block immediately), so nested
    /// store calls on the main thread are unaffected.
    func sync<T>(_ block: () -> T) -> T {
        context.performAndWait(block)
    }

    /// Overridable post-fetch hook, default no-op. Subclasses whose entity
    /// has field-level-encrypted properties (TransactionStore,
    /// TransactionDetailStore) override this to decrypt in place.
    func postFetch(_ entity: Entity) {}

    /// Single-result fetch against an explicit predicate/sort, on an
    /// explicit context — the caller (subclass) is responsible for having
    /// already entered `sync{}` or `context.performAndWait` as appropriate;
    /// this method itself does no context confinement, matching every
    /// existing store's `fetchByIdNoWrap`/explicit-context convention.
    func fetchOne(predicate: NSPredicate, sort: [NSSortDescriptor]?, in context: NSManagedObjectContext) -> Entity? {
        let request = NSFetchRequest<Entity>(entityName: Entity.entity().name ?? String(describing: Entity.self))
        request.predicate = predicate
        request.sortDescriptors = sort
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        postFetch(result)
        return result
    }

    /// Bounded fetch — `limit`/`offset` applied via NSFetchRequest, same as
    /// every existing `fetch*Page` method.
    func fetchPage(predicate: NSPredicate, sort: [NSSortDescriptor]?, limit: Int, offset: Int, in context: NSManagedObjectContext) -> [Entity] {
        let request = NSFetchRequest<Entity>(entityName: Entity.entity().name ?? String(describing: Entity.self))
        request.predicate = predicate
        request.sortDescriptors = sort
        request.fetchLimit = limit
        request.fetchOffset = offset
        let results = (try? context.fetch(request)) ?? []
        results.forEach { postFetch($0) }
        return results
    }

    /// Unbounded fetch matching a predicate — same shape as every existing
    /// `fetchAll`/`fetchBy*` method with no pagination.
    func fetchAllMatching(predicate: NSPredicate, sort: [NSSortDescriptor]?, in context: NSManagedObjectContext) -> [Entity] {
        let request = NSFetchRequest<Entity>(entityName: Entity.entity().name ?? String(describing: Entity.self))
        request.predicate = predicate
        request.sortDescriptors = sort
        let results = (try? context.fetch(request)) ?? []
        results.forEach { postFetch($0) }
        return results
    }
}
