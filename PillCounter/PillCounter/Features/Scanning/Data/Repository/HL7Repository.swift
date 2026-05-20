//
//  HL7Repository.swift
//  PillCounter
//

import ComposeApp

protocol HL7Repository {

    /// Resolves drug (local first → API fallback) and creates a single transaction.
    func resolveAndCreateTransaction(
        ndc: String,
        drugName: String,
        countType: CountType,
        targetCount: Int32?,
        rxNo: String?
    ) async throws -> PillCountTransactionEntity?

    /// Resolves all medications and creates a batch with one transaction per drug.
    func createBatchTransactions(
        medications: [MedicationData],
        requestId: String,
        bucketId: String
    ) async throws
}

enum HL7RepositoryError: Error {
    case drugNotFound
    case userNotFound
    case batchCreationFailed
}
