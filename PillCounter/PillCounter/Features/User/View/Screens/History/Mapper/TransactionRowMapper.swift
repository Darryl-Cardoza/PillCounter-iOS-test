//
//  TransactionRowMapper.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//

struct TransactionRowMapper {
    
    static func map(
        txn: PillCountTransactionEntity
    ) -> TransactionRowData {
        
        let details =
        (txn.pillCountTransactionDetails?.allObjects as? [PillCountTransactionDetailsEntity] ?? [])
            .filter { !$0.is_deleted }
        
        let totalCount = details.reduce(0) { $0 + Int($1.pill_count) }
        
        return TransactionRowData(
            id: txn.txn_id,
            ndc: txn.drug?.ndc ?? "",
            drugName: txn.drug?.drug_name ?? "Unknown Pill",
            createdAt: txn.created_at,
            barcodeImagePath: txn.barcode_image,
            pillCount: totalCount,
            targetCount: Int(txn.target_count),
            countType: txn.count_type ?? "",
            status: txn.status ?? "",
            note: txn.note,
            bucketId: txn.bucket_id ?? "",
            drugType: txn.drug?.drug_type ?? ""
        )
    }
}
