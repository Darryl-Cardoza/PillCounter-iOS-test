//
//  HL7RepositoryImpl.swift
//  PillCounter
//

import ComposeApp

final class HL7RepositoryImpl: HL7Repository {

    // MARK: - Dependencies
    private let drugDAO = DrugMasterDAO.shared
    private let txnDAO = TransactionDAO.shared
    private let userDAO = UserDAO.shared
    private let batchDAO = BatchDAO.shared
    private let controlledRepo = ControlledRepository.shared

    // MARK: - HL7Repository

    func resolveAndCreateTransaction(
        ndc: String,
        drugName: String,
        countType: CountType,
        targetCount: Int32?,
        rxNo: String?
    ) async throws -> PillCountTransactionEntity? {

        let trimmedNdc = ndc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNdc.isEmpty else { throw HL7RepositoryError.drugNotFound }

        // 1. Resolve drug — local first, API fallback
        let (drugId, resolvedName) = try await resolveDrug(ndc: trimmedNdc, fallbackName: drugName)

        // 2. Fetch user
        guard let user = userDAO.fetchByUserId(AppStorageManager.shared.userId ?? "") else {
            throw HL7RepositoryError.userNotFound
        }

        // 3. Create transaction
        let txn = txnDAO.create(
            for: user,
            drugId: drugId,
            countType: countType,
            isFromPms: true,
            targetCount: targetCount ?? 0,
            isControlled: true,
            rxNo: rxNo
        )

        return txn
    }

    func createBatchTransactions(
        medications: [MedicationData],
        requestId: String,
        bucketId: String
    ) async throws {

        guard !medications.isEmpty else { return }

        // 1. Resolve all drugs first
        struct ResolvedItem {
            let drugId: Int64
            let resolvedName: String
        }

        var resolvedItems: [ResolvedItem] = []

        for med in medications {
            let ndc = med.drugCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ndc.isEmpty else { continue }

            do {
                let (drugId, name) = try await resolveDrug(ndc: ndc, fallbackName: med.drugName)
                resolvedItems.append(ResolvedItem(drugId: drugId, resolvedName: name))
            } catch {
                // skip unresolvable drugs, continue batch
                Log("HL7: Skipping NDC \(ndc) — \(error)")
                continue
            }
        }

        guard !resolvedItems.isEmpty else { return }

        // 2. Create batch
        let batchId = Int64(Date().timeIntervalSince1970 * 1000)
        try createBatch(batchId: batchId, bucketId: bucketId, requestId: requestId)

        // 3. Fetch user once
        guard let user = userDAO.fetchByUserId(AppStorageManager.shared.userId ?? "") else {
            throw HL7RepositoryError.userNotFound
        }

        // 4. Create one transaction per resolved drug
        for item in resolvedItems {
            txnDAO.create(
                for: user,
                drugId: item.drugId,
                countType: .REGULAR,
                batchId: batchId,
                isFromPms: true,
                targetCount: 0,
                bucketId: bucketId.isEmpty ? nil : bucketId
            )
        }
    }

    // MARK: - Private Helpers

    /// Checks local DB first, falls back to controlled drug API.
    /// Saves to local DB on API success.
    /// Returns (drugId, resolvedName).
    private func resolveDrug(ndc: String, fallbackName: String) async throws -> (Int64, String) {

        // Local hit
        if let local = drugDAO.fetchByNdc(ndc),
           let name = local.drug_name, !name.isEmpty {
            Log("HL7: Drug found locally → \(name)")
            return (local.drug_id, name)
        }

        // API fallback
        let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)
        let response = try await controlledRepo.getControlledDrugInfo(ndcValidationRequest: request)

        guard let lookup = response.data?.scannedNdc?.lookupName, !lookup.isEmpty else {
            throw HL7RepositoryError.drugNotFound
        }

        let newDrugId = generateDrugId()

        drugDAO.fetchOrCreate(ndc: ndc, drugId: newDrugId)
        drugDAO.update(
            drugId: newDrugId,
            drugName: lookup,
            ndc: ndc,
            drugType: response.data?.scannedNdc?.deaSchedule,
            packageQty: response.data?.scannedNdc?.safeQuantity ?? 0
        )

        Log("HL7: Drug saved from API → \(lookup)")
        return (newDrugId, lookup)
    }

    private func createBatch(batchId: Int64, bucketId: String, requestId: String) throws {
        let context = CoreDataManager.shared.context
        let batch = BatchCountEntity(context: context)
        batch.batch_id = batchId
        batch.start_date_time = batchId
        batch.status = CountStatus.PARTIAL.rawValue
        batch.is_deleted = false
        batch.bucket_id = bucketId
        batch.req_id_from_pms = requestId
        batch.is_synced = false
        CoreDataManager.shared.save(context: context)
    }

    private func generateDrugId() -> Int64 {
        let key = AppStorageManager.AppStorageKeys.drugIdCounter
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
