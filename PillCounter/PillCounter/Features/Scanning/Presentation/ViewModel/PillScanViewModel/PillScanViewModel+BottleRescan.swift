//
//  PillScanViewModel+BottleRescan.swift
//  PillCounter
//

import Foundation

extension PillScanViewModel {

    /// The bottle currently being counted from — always the last entry in the
    /// transaction's bottle list (bottles are append-only, never reordered).
    func activeBottle(txnId: Int64) -> BottleInfo? {
        transactionDAO.getBottleList(txnId: txnId).last
    }

    /// Stages the first bottle for a dispense transaction once the NDC scan that
    /// started the count resolves. No-ops if the transaction already has a bottle
    /// list (guards against clobbering an in-progress count on app resume) or if
    /// this isn't a dispense transaction.
    func stageFirstBottleIfNeeded(rawBarcode: String?) {
        guard let txn = currentTransaction, txn.is_dispense == true else { return }
        guard transactionDAO.getBottleList(txnId: txn.txn_id).isEmpty else { return }

        let decoded = decoder.decode(rawBarcode ?? "")
        let bottle = BottleInfo(
            lotNumber: decoded.lotNumber,
            expirationDate: DateUtils.formatExpiryMMddyyyy(decoded.expirationDate),
            serialNumber: decoded.serialNumber,
            txnDetailsIds: [],
            scannedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        transactionDAO.setBottleList(txnId: txn.txn_id, [bottle])
    }

    // MARK: - Rescan during counting

    /// Called from the barcode-metadata delegate while a dispense count is
    /// actively in progress. Resolves the scan locally only (never hits the
    /// network); a miss or a mismatched drug is a silent no-op. Otherwise
    /// compares against the active bottle and either toasts (duplicate),
    /// stages an "add bottle" confirmation, or stages a "replace bottle"
    /// confirmation, depending on whether anything has been counted yet.
    func handleBottleRescan(rawBarcode: String) {
        guard !isProcessingBottleRescan else { return }
        guard let txn = currentTransaction, txn.is_dispense == true else { return }
        guard currentControlledStep != .vial else { return }

        isProcessingBottleRescan = true
        defer { isProcessingBottleRescan = false }

        let decoded = decoder.decode(rawBarcode)

        let resolvedDrug = decoded.gtin.flatMap { drugMasterDAO.fetchByGtin($0) }
            ?? drugMasterDAO.fetchByNdc(decoded.gtin ?? "")
        guard let resolvedDrug, resolvedDrug.drug_id == txn.drug_id else { return }

        let bottles = transactionDAO.getBottleList(txnId: txn.txn_id)
        let candidate = BottleInfo(
            lotNumber: decoded.lotNumber,
            expirationDate: DateUtils.formatExpiryMMddyyyy(decoded.expirationDate),
            serialNumber: decoded.serialNumber,
            txnDetailsIds: [],
            scannedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )

        if let last = bottles.last,
           last.lotNumber == candidate.lotNumber,
           last.expirationDate == candidate.expirationDate,
           last.serialNumber == candidate.serialNumber {
            showToastMessage(text: L10n.BarcodeScan.bottleAlreadyScanned)
            return
        }

        pendingBottleRescan = candidate
        if transactionDetailDAO.totalCount(txnId: txn.txn_id) > 0 {
            showAddBottlePopup = true
        } else {
            showReplaceBottlePopup = true
        }
    }

    func confirmAddBottle() {
        guard let txn = currentTransaction, let candidate = pendingBottleRescan else { return }
        transactionDAO.appendBottle(txnId: txn.txn_id, candidate)
        pendingBottleRescan = nil
        showAddBottlePopup = false
    }

    func cancelAddBottle() {
        pendingBottleRescan = nil
        showAddBottlePopup = false
    }

    func confirmReplaceBottle() {
        guard let txn = currentTransaction, let candidate = pendingBottleRescan else { return }
        transactionDAO.replaceLastBottle(txnId: txn.txn_id, candidate)
        pendingBottleRescan = nil
        showReplaceBottlePopup = false
    }

    func cancelReplaceBottle() {
        pendingBottleRescan = nil
        showReplaceBottlePopup = false
    }
}
