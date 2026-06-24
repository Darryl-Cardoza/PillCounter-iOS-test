//
//  TransactionRowMapper.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//
import Foundation


extension PillCountTransactionEntity {

    func toRowData(pillCount: Int? = nil) -> TransactionRowData {

        let details =
        (self.pillCountTransactionDetails?.allObjects as? [PillCountTransactionDetailsEntity] ?? [])
            .filter { !$0.is_deleted }

        let totalCount = pillCount ?? details.reduce(0) { $0 + Int($1.pill_count) }

        return TransactionRowData(
            id: String(self.txn_id),
            ndc: self.drug?.ndc ?? "",
            drugName: self.drug?.drug_name ?? "Unknown Pill",
            createdAt: self.created_at,
            barcodeImagePath: self.barcode_image,
            pillCount: totalCount,
            targetCount: Int(self.target_count),
            countType: self.count_type ?? "",
            status: self.status ?? "",
            note: self.note,
            bucketId: self.bucket_id ?? "",
            drugType: self.drug?.drug_type ?? "",
            strength: self.drug?.strength ?? "",
            dosageForm: self.drug?.dosage_form ?? ""
        )
    }
}
