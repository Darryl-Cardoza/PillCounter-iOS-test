//
//  StockInfoUIModel.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//

//
struct StockData: Identifiable {
    let id: Int64
    let batchId: Int64
    let createdAt: Int64
    let ndcCount: Int64
    let status: String
    let bucketId: String
    let isFromPms: Bool

    /// Filter-only, raw field — Dashboard's cycle-count/pending-batch
    /// stat-card filters check emptiness explicitly (an empty non-nil
    /// string is a real "not yet from PMS" state, distinct from `isFromPms`'s
    /// nil-check semantics used for display).
    let reqIdFromPms: String?
}
