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
    let targetCount: Int
    let status: String
    let bucketId: String
    let isFromPms: Bool
}
