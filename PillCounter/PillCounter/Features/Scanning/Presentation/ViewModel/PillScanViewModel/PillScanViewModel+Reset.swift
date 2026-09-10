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

    /// Transaction-wide (not step-scoped) mirror of what `resetCurrentTransaction()` wipes.
    func hasAnythingToResetForCurrentTransaction() -> Bool {
        guard let txnId = currentTransaction?.txn_id else { return false }

        if !transactionDetailDAO.fetchAll(txnId: txnId).isEmpty { return true }
        if !transactionDAO.getBottleList(txnId: txnId).isEmpty { return true }
        if currentTransaction?.is_ndc_verfied == true { return true }
        if pendingBarcodeImagePath != nil { return true }
        if vialCapturedImagePath != nil { return true }

        return false
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
    /// Returns `false` (and leaves everything untouched) if the hard delete
    /// failed to persist — the caller must not treat this as a successful
    /// reset (e.g. must not navigate back to the barcode-scan step).
    @discardableResult
    func resetCurrentTransaction() -> Bool {
        guard let txn = currentTransaction, canResetCurrentTransaction else { return false }
        let txnId = txn.txn_id

        let result = transactionDetailDAO.hardDeleteAll(txnId: txnId)
        guard result.success else { return false }
        result.imagePaths.forEach { PhotoFileManager.shared.deleteImage(fileName: $0) }

        // Cancel any in-flight NDC check — otherwise its completion lands
        // after reset and silently re-populates the flags reset just cleared.
        ndcCheckTask?.cancel()
        ndcCheckTask = nil
        isCheckingNdc = false

        // Clear the bottle list too — its entries reference the detail rows
        // just hard-deleted above (txnDetailsIds) and carry their own
        // barcodeImagePath image. Leaving it behind also blocks re-staging:
        // stageFirstBottleIfNeeded no-ops once the list is non-empty.
        for bottle in transactionDAO.getBottleList(txnId: txnId) {
            if let barcodeImagePath = bottle.barcodeImagePath {
                PhotoFileManager.shared.deleteImage(fileName: barcodeImagePath)
            }
        }
        transactionDAO.setBottleList(txnId: txnId, [])

        transactionDAO.updateNdcVerified(txnId: txnId, verified: false)
        transactionDAO.clearWorkflowStep(txnId: txnId)

        currentTransactionTransactionDetails = []
        currentControlledTargetCount = nil

        // Every other leftover flag/scratch-state a fresh transaction never
        // carries — same "not yet resolved" state described above.
        if let pendingBarcodeImagePath {
            PhotoFileManager.shared.deleteImage(fileName: pendingBarcodeImagePath)
        }
        pendingBarcodeImagePath = nil
        if let vialCapturedImagePath {
            PhotoFileManager.shared.deleteImage(fileName: vialCapturedImagePath)
        }
        vialCapturedImagePath = nil
        capturedVialImage = nil
        targetCount = ["", "", "", ""]
        note = ""
        showAddBottlePopup = false
        showReplaceBottlePopup = false
        pendingBottleRescan = nil
        pendingBottleRescanImage = nil
        isNdcAdded = false
        ndcMismatchRestartFlow = false
        shouldAutoProceedToCount = false
        showSkipBackCountPopup = false

        return true
    }
}
