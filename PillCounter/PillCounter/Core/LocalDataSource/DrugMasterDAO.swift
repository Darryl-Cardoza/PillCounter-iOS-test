//
//  DrugMasterDAO.swift
//  PillCounter
//

import CoreData

final class DrugMasterDAO {

    static let shared = DrugMasterDAO()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    // MARK: - Create / Upsert

    func saveFromResponse(_ response: GetDrugResponse, ndc: String, drugId: Int64) {
        guard let pillData = response.data else { return }
        let entity = fetchOrCreate(ndc: ndc, drugId: drugId)
        entity.drug_name = pillData.genericName
        entity.drug_type = ""
        entity.ndc = ndc
        CoreDataManager.shared.save(context: context)
    }

    func saveManual(
        ndc: String,
        gtin: String = "",
        drugId: Int64,
        drugName: String,
        drugType: String? = nil,
        packageQty: Int32 = 0
    ) {
        let entity = fetchOrCreate(ndc: ndc, drugId: drugId)
        if entity.drug_name == nil || entity.drug_name!.isEmpty { entity.drug_name = drugName }
        if !gtin.isEmpty { entity.gtin = gtin }
        if let drugType { entity.drug_type = drugType }
        if packageQty > 0 { entity.package_qty = packageQty }
        entity.ndc = ndc
        CoreDataManager.shared.save(context: context)
    }

    @discardableResult
    func fetchOrCreate(ndc: String, drugId: Int64) -> DrugMasterEntity {
        if let existing = fetchByNdc(ndc) { return existing }
        let entity = DrugMasterEntity(context: context)
        entity.drug_id = drugId
        entity.created_at = Int64(Date().timeIntervalSince1970 * 1000)
        return entity
    }

    // MARK: - Read

    func fetchByNdc(_ ndc: String) -> DrugMasterEntity? {
        let request: NSFetchRequest<DrugMasterEntity> = DrugMasterEntity.fetchRequest()
        request.predicate = NSPredicate(format: "ndc == %@", ndc)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchByGtin(_ gtin: String) -> DrugMasterEntity? {
        let request: NSFetchRequest<DrugMasterEntity> = DrugMasterEntity.fetchRequest()
        request.predicate = NSPredicate(format: "gtin == %@", gtin)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchById(_ drugId: Int64) -> DrugMasterEntity? {
        let request: NSFetchRequest<DrugMasterEntity> = DrugMasterEntity.fetchRequest()
        request.predicate = NSPredicate(format: "drug_id == %lld", drugId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchAll() -> [DrugMasterEntity] {
        let request: NSFetchRequest<DrugMasterEntity> = DrugMasterEntity.fetchRequest()
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - Update

    func update(
        drugId: Int64,
        drugName: String? = nil,
        ndc: String? = nil,
        gtin: String? = nil,
        drugType: String? = nil,
        packageQty: Int32? = nil
    ) {
        guard let drug = fetchById(drugId) else { return }
        if let drugName { drug.drug_name = drugName }
        if let ndc { drug.ndc = ndc }
        if let gtin, !gtin.isEmpty { drug.gtin = gtin }
        if let drugType { drug.drug_type = drugType }
        if let packageQty, packageQty > 0 { drug.package_qty = packageQty }
        CoreDataManager.shared.save(context: context)
    }

    // MARK: - Delete

    func deduplicate() {
        var seen: [String: DrugMasterEntity] = [:]
        for drug in fetchAll() {
            let key = drug.ndc ?? ""
            guard !key.isEmpty else { continue }
            if let existing = seen[key] {
                if drug.created_at < existing.created_at {
                    context.delete(existing)
                    seen[key] = drug
                } else {
                    context.delete(drug)
                }
            } else {
                seen[key] = drug
            }
        }
        CoreDataManager.shared.save(context: context)
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = DrugMasterEntity.fetchRequest()

        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        } catch {
            print("Failed to delete DrugMasterEntity: \(error)")
        }
    }
}
