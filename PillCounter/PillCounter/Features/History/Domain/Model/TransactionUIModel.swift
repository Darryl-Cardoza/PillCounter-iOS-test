//
//  TransactionUIModel.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//
struct TransactionRowData: Identifiable {
    let id: String
    let ndc: String
    let drugName: String
    let createdAt: Int64
    let barcodeImagePath: String?
    let drugImagePath: String?

    let pillCount: Int
    let targetCount: Int
    let countType: String
    let status: String
    let note: String?
    let bucketId: String
    let drugType: String
    let strength: String
    let dosageForm: String

    // Filter/navigation-only fields — not rendered by every row view that
    // uses this DTO, but needed by Dashboard's stat-card filters and its
    // Today's Queue tap-to-resume routing (see DashboardQueueItem).
    let txnId: Int64
    let txnPriority: String?
    let isHazardous: Bool
    let isDispense: Bool
    let batchId: Int64
    let isNdcVerified: Bool
}
