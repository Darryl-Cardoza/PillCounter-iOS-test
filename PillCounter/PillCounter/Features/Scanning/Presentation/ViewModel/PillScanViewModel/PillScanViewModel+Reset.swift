//
//  PillScanViewModel+Reset.swift
//  PillCounter
//
//  "Reset Transaction" — hard-deletes all counted details/images for the
//  current dispense transaction and restarts it from the scan step, as if
//  the transaction had just been created.
//

import Foundation

extension PillScanViewModel {

    /// True only while the transaction is still in progress — reset is not
    /// offered once a transaction has been completed.
    var canResetCurrentTransaction: Bool {
        guard let status = currentTransaction?.status else { return false }
        return status != CountStatus.COMPLETED.rawValue
            && status != CountStatus.FORCE_COMPLETED.rawValue
    }

    /// Hard-deletes every detail row (and its backing image file) for the
    /// current transaction, clears its NDC-verified flag and persisted
    /// workflow step, and clears in-memory count state — same "not yet
    /// resolved" state a brand-new transaction starts in (see
    /// `TransactionStore.create`'s `workFlowStep: nil` default). The screen
    /// re-derives the real first controlled step itself once the operator
    /// re-scans and `getControlledStep` runs again — this function does not
    /// set `currentControlledStep`, since `.scan` is never a real persisted
    /// workflow step and setting it here would make `getWorkflowStep` treat
    /// the transaction as already resolved instead of re-deriving it.
    func resetCurrentTransaction() {
        guard let txn = currentTransaction, canResetCurrentTransaction else { return }
        let txnId = txn.txn_id

        let deletedImagePaths = transactionDetailDAO.hardDeleteAll(txnId: txnId)
        deletedImagePaths.forEach { PhotoFileManager.shared.deleteImage(fileName: $0) }

        transactionDAO.updateNdcVerified(txnId: txnId, verified: false)
        transactionDAO.clearWorkflowStep(txnId: txnId)

        currentTransactionTransactionDetails = []
        currentControlledTargetCount = nil
    }
}
