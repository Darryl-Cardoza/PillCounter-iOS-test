//
//  DrugMasterDAO.swift
//  PillCounter
//

import CoreData
import UIKit

final class DrugCatalogStore {

    static let shared = DrugCatalogStore()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    func saveManual(
        ndc: String,
        gtin: String = "",
        drugId: Int64,
        drugName: String,
        drugType: String? = nil,
        strength: String? = nil,
        dosageForm: String? = nil,
        packageQty: Int32 = 0,
        isHazardous: Bool? = nil,
        imageUrl: String? = nil
    ) {
        let entity = fetchOrCreate(ndc: ndc, drugId: drugId)
        if !drugName.isEmpty { entity.drug_name = drugName }
        if !gtin.isEmpty { entity.gtin = gtin }
        if let drugType, !drugType.isEmpty { entity.drug_type = drugType }
        if let strength, !strength.isEmpty { entity.strength = strength }
        if let dosageForm, !dosageForm.isEmpty { entity.dosage_form = dosageForm }
        if packageQty > 0 { entity.package_qty = packageQty }
        if let isHazardous { entity.is_hazardous = isHazardous }
        entity.ndc = ndc
        CoreDataManager.shared.save(context: context)
        print("💊 [DrugMasterDAO] SAVED — ndc: \(ndc), drugId: \(drugId), drugName: \(drugName)")
        _ = fetchAll()

        // Image is downloaded once and cached locally; existing local path is never overwritten.
        if entity.drug_image == nil, let imageUrl, let url = URL(string: imageUrl) {
            downloadAndStoreImage(from: url, drugId: entity.drug_id)
        }
    }

    /// Downloads the drug image once and stores its local file path on the entity,
    /// so every subsequent read serves from disk instead of the network.
    private func downloadAndStoreImage(from url: URL, drugId: Int64) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self, let data, error == nil, let image = UIImage(data: data) else {
                print("❌ [DrugMasterDAO] image download failed for drugId \(drugId): \(String(describing: error))")
                return
            }
            guard let fileName = PhotoFileManager.shared.saveImage(image) else { return }
            self.context.perform {
                guard let entity = self.fetchById(drugId), entity.drug_image == nil else { return }
                entity.drug_image = fileName
                CoreDataManager.shared.save(context: self.context)
                print("💊 [DrugMasterDAO] IMAGE SAVED — drugId: \(drugId), file: \(fileName)")
            }
        }.resume()
    }

    /// Single entry point for persisting an API `NdcDrug` response into the drug master.
    ///
    /// Every flow that calls the drug API (Rx, controlled substitution, HL7, stock count)
    /// routes its save through here so ALL fields — including `strength` and `dosage_form` —
    /// are written consistently. Delegates to `saveManual`, which only overwrites a field when
    /// the incoming value is non-empty, so later API calls fill in missing data without wiping
    /// good data already on the record.
    ///
    /// - Parameters:
    ///   - ndc: Storage key. Callers decide which NDC to key under (e.g. HL7 keeps the original
    ///          scanned NDC, not the API's package NDC).
    ///   - drugId: Id assigned only if the record is newly created.
    ///   - drug: The decoded API DTO.
    ///   - gtin: Optional GTIN to backfill.
    /// - Returns: The persisted entity (so callers can read back the resolved `drug_id`).
    @discardableResult
    func upsertFromApi(
        ndc: String,
        drugId: Int64,
        drug: NdcDrug,
        gtin: String = ""
    ) -> DrugMasterEntity? {
        saveManual(
            ndc:  ndc,
            gtin:  gtin,
            drugId:  drugId,
            drugName: drug.lookupName ?? "",
            drugType:  drug.scheduleType,
            strength: drug.primaryStrength,
            dosageForm: drug.primaryDosageForm,
            packageQty:  drug.safeQuantity,
            isHazardous: drug.isHazardous,
            imageUrl: drug.images?.primary
        )
        return fetchByNdc(ndc)
    }

    @discardableResult
    func fetchOrCreate(ndc: String, drugId: Int64) -> DrugMasterEntity {
        if let existing = fetchByNdc(ndc) { return existing }
        let entity = DrugMasterEntity(context: context)
        entity.drug_id = drugId
        entity.created_at = Int64(Date().timeIntervalSince1970 * 1000)
        print("💊 [DrugMasterDAO] CREATED — ndc: \(ndc), drugId: \(drugId)")
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
        print("Gtin\(try? context.fetch(request).first)")
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
        let results = (try? context.fetch(request)) ?? []
        StoreLogger.log(
            dao: "DrugMasterDAO", op: "fetchAll",
            columns: ["drug_id", "ndc", "drug_name", "gtin", "drug_type", "pkg_qty", "is_hazardous", "strengh", "dosage_form"],
            rows: results.map { [
                "\($0.drug_id)",
                $0.ndc ?? "-",
                $0.drug_name ?? "-",
                $0.gtin ?? "-",
                $0.drug_type ?? "-",
                "\($0.package_qty)",
                "\($0.is_hazardous)",
                $0.strength ?? "",
                $0.dosage_form ?? ""
            ]}
        )
        return results
    }

    // MARK: - Update

    func update(
        drugId: Int64,
        drugName: String? = nil,
        ndc: String? = nil,
        gtin: String? = nil,
        drugType: String? = nil,
        strength: String? = nil,
        dosageForm: String? = nil,
        packageQty: Int32? = nil,
        isHazardous: Bool? = nil
    ) {
        guard let drug = fetchById(drugId) else { return }
        if let drugName { drug.drug_name = drugName }
        if let ndc { drug.ndc = ndc }
        if let gtin, !gtin.isEmpty { drug.gtin = gtin }
        if let drugType { drug.drug_type = drugType }
        if let strength { drug.strength = strength }
        if let dosageForm { drug.dosage_form = dosageForm }
        if let packageQty, packageQty > 0 { drug.package_qty = packageQty }
        if let isHazardous { drug.is_hazardous = isHazardous }
        CoreDataManager.shared.save(context: context)
        print("💊 [DrugMasterDAO] UPDATED — drugId: \(drugId), drugName: \(drugName ?? "-"), ndc: \(ndc ?? "-"), gtin: \(gtin ?? "-")")
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
        print("💊 [DrugMasterDAO] DEDUPLICATED — removed duplicates, kept \(seen.count) unique NDC entries")
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = DrugMasterEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            print("💊 [DrugMasterDAO] DELETED ALL — all DrugMaster records removed")
        } catch {
            print("Failed to delete DrugMasterEntity: \(error)")
        }
    }
}
