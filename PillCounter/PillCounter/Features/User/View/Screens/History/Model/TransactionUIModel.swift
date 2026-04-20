//
//  TransactionUIModel.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//
struct TransactionRowData: Identifiable {
    let id: Int64
    
    let ndc: String
    let drugName: String
    let createdAt: Int64
    let barcodeImagePath: String?
    
    let pillCount: Int
    let targetCount: Int
    let countType: String
    let status: String
    let note: String?
    let bucketId: String
    let drugType: String
}
