//
//  PillScanViewModel+BottleRescan.swift
//  PillCounter
//

import Foundation
import UIKit

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
            scannedAt: Int64(Date().timeIntervalSince1970 * 1000),
            barcodeImagePath: pendingBarcodeImagePath
        )
        transactionDAO.setBottleList(txnId: txn.txn_id, [bottle])
        pendingBarcodeImagePath = nil
    }

    // MARK: - Rescan during counting

    /// Called from the barcode-metadata delegate while a dispense count is
    /// actively in progress. Resolves the scan locally only (never hits the
    /// network); a miss or a mismatched drug is a silent no-op. Otherwise
    /// compares against the active bottle and either toasts (duplicate),
    /// stages an "add bottle" confirmation, or stages a "replace bottle"
    /// confirmation, depending on whether anything has been counted yet.
    func handleBottleRescan(rawBarcode: String, snapshot: UIImage? = nil) {
        print("📦 [BottleRescan] scanned raw: \(rawBarcode)")
        guard !isProcessingBottleRescan else {
            print("📦 [BottleRescan] ignored — already processing a scan")
            return
        }
        guard let txn = currentTransaction, txn.is_dispense == true else {
            print("📦 [BottleRescan] ignored — no active dispense transaction")
            return
        }
        guard currentControlledStep == .containerInitiate || currentControlledStep == .targetVerification else {
            print("📦 [BottleRescan] ignored — not on containerInitiate/targetVerification step")
            return
        }

        isProcessingBottleRescan = true
        defer { isProcessingBottleRescan = false }

        let decoded = decoder.decode(rawBarcode)
        print("📦 [BottleRescan] decoded gtin: \(decoded.gtin ?? "nil"), lot: \(decoded.lotNumber ?? "nil"), serial: \(decoded.serialNumber ?? "nil")")

        let resolvedDrug = decoded.gtin.flatMap { drugMasterDAO.fetchByGtin($0) }
            ?? drugMasterDAO.fetchByNdc(rawBarcode)
        guard let resolvedDrug else {
            print("📦 [BottleRescan] ignored — drug not found locally for gtin/ndc")
            return
        }
        guard resolvedDrug.drug_id == txn.drug_id else {
            print("📦 [BottleRescan] ignored — resolved drug_id \(resolvedDrug.drug_id) does not match txn drug_id \(txn.drug_id)")
            return
        }

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

        // Snapshot is taken at detection time (passed in here) so the confirmation
        // popup always saves the frame that was actually scanned, not whatever the
        // camera happens to be pointed at when the user taps confirm. It's only
        // persisted to disk once the user confirms — a cancelled or duplicate scan
        // never writes a photo.
        pendingBottleRescan = candidate
        pendingBottleRescanImage = snapshot
        if transactionDetailDAO.totalCount(txnId: txn.txn_id) > 0 {
            showAddBottlePopup = true
        } else {
            showReplaceBottlePopup = true
        }
    }

    func confirmAddBottle(image: UIImage? = nil) {
        guard let txn = currentTransaction, var candidate = pendingBottleRescan else { return }
        if let image = image ?? pendingBottleRescanImage {
            candidate.barcodeImagePath = PhotoFileManager.shared.saveImage(image)
        }
        transactionDAO.appendBottle(txnId: txn.txn_id, candidate)
        pendingBottleRescan = nil
        pendingBottleRescanImage = nil
        showAddBottlePopup = false
    }

    func cancelAddBottle() {
        pendingBottleRescan = nil
        pendingBottleRescanImage = nil
        showAddBottlePopup = false
    }

    func confirmReplaceBottle(image: UIImage? = nil) {
        guard let txn = currentTransaction, var candidate = pendingBottleRescan else { return }
        if let image = image ?? pendingBottleRescanImage {
            candidate.barcodeImagePath = PhotoFileManager.shared.saveImage(image)
        }
        transactionDAO.replaceLastBottle(txnId: txn.txn_id, candidate)
        pendingBottleRescan = nil
        pendingBottleRescanImage = nil
        showReplaceBottlePopup = false
    }

    func cancelReplaceBottle() {
        pendingBottleRescan = nil
        pendingBottleRescanImage = nil
        showReplaceBottlePopup = false
    }
}
