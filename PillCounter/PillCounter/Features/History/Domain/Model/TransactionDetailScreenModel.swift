//
//  TransactionDetailScreenModel.swift
//  PillCounter
//

/// Plain UI-facing snapshot of everything `HistoryTransactionDetailView`
/// reads off a transaction and its detail rows. Built entirely inside one
/// background Core Data context (fetch + relationship reads + per-row
/// decrypt all happen there — see `HistoryViewModel.prepareDetailScreen`),
/// so the view never touches an `NSManagedObject` fetched off-main.
struct TransactionDetailScreenModel {
    let txnId: Int64
    let drugName: String
    let ndc: String
    let drugType: String
    let note: String?
    let targetCount: Int32
    let createdAt: Int64
    let isDispense: Bool
    let isSubstitute: Bool
    let substituteDrugName: String?
    let substituteNdc: String?
    let bottleInfoListJson: String?
    let detailsByStep: [ControlledStep: [TransactionDetailRowUIModel]]
}

/// One `PillCountTransactionDetailsEntity` row, flattened to the fields
/// `HistoryTransactionDetailView` actually renders.
struct TransactionDetailRowUIModel: Identifiable {
    let id: Int64
    let imagePath: String?
    let pillCount: Int32
    let createdAt: Int64
}
