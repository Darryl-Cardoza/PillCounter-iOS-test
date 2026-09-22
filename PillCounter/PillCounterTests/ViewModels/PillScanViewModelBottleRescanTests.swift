//
//  PillScanViewModelBottleRescanTests.swift
//  PillCounterTests
//
//  Tests for PillScanViewModel+BottleRescan, built with fully-mocked DAOs so no
//  CoreData access happens in this suite. `PillScanViewModel` is @MainActor.
//

import Testing
import Foundation
@testable import PillCounter

@MainActor
@Suite
struct PillScanViewModelBottleRescanTests {

    // MARK: - Fixture helpers

    private func makeViewModel(
        transactionDAO: MockTransactionDataSource = MockTransactionDataSource(),
        transactionDetailDAO: MockTransactionDetailDataSource = MockTransactionDetailDataSource(),
        drugMasterDAO: MockDrugCatalogDataSource = MockDrugCatalogDataSource()
    ) -> PillScanViewModel {
        PillScanViewModel(
            drugMasterDAO: drugMasterDAO,
            transactionDAO: transactionDAO,
            transactionDetailDAO: transactionDetailDAO,
            batchDAO: MockBatchDataSource(),
            stockTxnDAO: MockStockTxnDataSource(),
            bottleInfoDAO: MockBottleInfoDataSource(),
            userDataLocalStorage: MockUserDataSource(),
            decoder: BarcodeAndQRDecoder(),
            userRepo: MockUserRepository(),
            controlledRepo: MockControlledRepository()
        )
    }

    private func makeTransaction(txnId: Int64, drugId: Int64, isDispense: Bool) -> PillCountTransactionEntity {
        let txn = PillCountTransactionEntity(context: MockCoreData.context)
        txn.txn_id = txnId
        txn.drug_id = drugId
        txn.is_dispense = isDispense
        txn.drug = makeDrug(drugId: drugId)
        return txn
    }

    private func makeDrug(drugId: Int64, gtin: String? = nil) -> DrugMasterEntity {
        let drug = DrugMasterEntity(context: MockCoreData.context)
        drug.drug_id = drugId
        // Realistic 11-digit NDC (5-4-2, no dashes) so ndcNormalized comparisons
        // exercise the real digit-matching path instead of stripping letters.
        drug.ndc = String(format: "%05d%04d%02d", 0, drugId, 0)
        drug.gtin = gtin
        return drug
    }

    private let gs1WithFullInfo = "(01)00312345678906(10)LOT99(17)271231(21)SER77"

    // MARK: - activeBottle

    @Test func activeBottleReturnsLastEntryOrNilWhenEmpty() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)

        #expect(vm.activeBottle(txnId: 1) == nil)

        let b1 = BottleInfo(lotNumber: "A", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        let b2 = BottleInfo(lotNumber: "B", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 2)
        transactionDAO.setBottleList(txnId: 1, [b1, b2])

        #expect(vm.activeBottle(txnId: 1) == b2)
    }

    // MARK: - stageFirstBottleIfNeeded

    @Test func stageFirstBottleNoOpsWhenBottleListAlreadyNonEmpty() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn

        let existing = BottleInfo(lotNumber: "OLD", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        transactionDAO.setBottleList(txnId: 1, [existing])

        vm.stageFirstBottleIfNeeded(rawBarcode: gs1WithFullInfo)

        #expect(transactionDAO.getBottleList(txnId: 1) == [existing])
    }

    @Test func stageFirstBottleNoOpsForNonDispenseTxn() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: false)
        vm.currentTransaction = txn

        vm.stageFirstBottleIfNeeded(rawBarcode: gs1WithFullInfo)

        #expect(transactionDAO.getBottleList(txnId: 1) == [])
    }

    @Test func stageFirstBottleWithGS1BarcodeExtractsLotExpirySerial() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn

        vm.stageFirstBottleIfNeeded(rawBarcode: gs1WithFullInfo)

        let bottles = transactionDAO.getBottleList(txnId: 1)
        #expect(bottles.count == 1)
        #expect(bottles[0].lotNumber == "LOT99")
        #expect(bottles[0].serialNumber == "SER77")
        #expect(bottles[0].expirationDate == "12-31-2027")
        #expect(bottles[0].txnDetailsIds == [])
    }

    @Test func stageFirstBottleWithNonGS1BarcodeHasAllNilFields() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn

        vm.stageFirstBottleIfNeeded(rawBarcode: "not-a-gs1-barcode")

        let bottles = transactionDAO.getBottleList(txnId: 1)
        #expect(bottles.count == 1)
        #expect(bottles[0].lotNumber == nil)
        #expect(bottles[0].expirationDate == nil)
        #expect(bottles[0].serialNumber == nil)
    }

    // MARK: - handleBottleRescan guards

    @Test func handleBottleRescanNoOpsOnVialStep() {
        let transactionDAO = MockTransactionDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .vial
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 100, gtin: "00312345678906")

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showAddBottlePopup == false)
        #expect(vm.showReplaceBottlePopup == false)
        #expect(vm.pendingBottleRescan == nil)
    }

    @Test func handleBottleRescanNoOpsForNonDispenseTxn() {
        let transactionDAO = MockTransactionDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: false)
        vm.currentTransaction = txn
        vm.currentControlledStep = .scan
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 100, gtin: "00312345678906")

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showAddBottlePopup == false)
        #expect(vm.showReplaceBottlePopup == false)
    }

    @Test func handleBottleRescanSilentlyNoOpsOnLocalLookupMiss() {
        let transactionDAO = MockTransactionDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource() // nothing registered -> miss
        let vm = makeViewModel(transactionDAO: transactionDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .scan

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showAddBottlePopup == false)
        #expect(vm.showReplaceBottlePopup == false)
        #expect(vm.pendingBottleRescan == nil)
    }

    @Test func handleBottleRescanSilentlyNoOpsOnNdcMismatch() {
        let transactionDAO = MockTransactionDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .scan
        // Resolved drug exists locally but belongs to a DIFFERENT NDC than the txn's.
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 999, gtin: "00312345678906")

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showAddBottlePopup == false)
        #expect(vm.showReplaceBottlePopup == false)
    }

    @Test func handleBottleRescanMatchesOnNdcAcrossDifferentDrugIds() {
        // A second bottle of the identical NDC can resolve to a different
        // drug_id row than the transaction's (e.g. separate import batches) —
        // that must still be treated as a match, not rejected.
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .targetVerification
        transactionDetailDAO.totals[1] = 0
        // Same NDC as txn's drug (NDC-100), but a different drug_id (999).
        let sameNdcDifferentDrugId = makeDrug(drugId: 999, gtin: "00312345678906")
        sameNdcDifferentDrugId.ndc = txn.drug?.ndc
        drugMasterDAO.drugsByGtin["00312345678906"] = sameNdcDifferentDrugId

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showReplaceBottlePopup == true)
    }

    /// gs1WithFullInfo decodes to lot "LOT99"/exp "271231"/serial "SER77". A bottle
    /// with that exact lot/exp/serial scanned earlier in the batch — not just the
    /// immediately-previous scan — must still be caught as a duplicate, not offered
    /// as a new "Add bottle" candidate.
    @Test func handleBottleRescanTreatsMatchAnywhereInBottleListAsDuplicateNotJustLast() {
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .targetVerification
        transactionDetailDAO.totals[1] = 0
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 100, gtin: "00312345678906")

        let earlierMatch = BottleInfo(lotNumber: "LOT99", expirationDate: "12-31-2027", serialNumber: "SER77", txnDetailsIds: [], scannedAt: 1)
        let mostRecent = BottleInfo(lotNumber: "LOT-OTHER", expirationDate: "01-01-2028", serialNumber: "SER-OTHER", txnDetailsIds: [], scannedAt: 2)
        transactionDAO.setBottleList(txnId: 1, [earlierMatch, mostRecent])

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showAddBottlePopup == false)
        #expect(vm.showReplaceBottlePopup == false)
        #expect(vm.pendingBottleRescan == nil)
    }

    @Test func handleBottleRescanMatchesAcrossDashedAndPlainNdcFormatting() {
        // Different import paths can store the same NDC with or without dashes
        // (e.g. "00406-0124-10" vs "00406012410") — that must still match.
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        txn.drug?.ndc = "00406012410"
        vm.currentTransaction = txn
        vm.currentControlledStep = .targetVerification
        transactionDetailDAO.totals[1] = 0
        let dashedNdcDrug = makeDrug(drugId: 999, gtin: "00312345678906")
        dashedNdcDrug.ndc = "00406-0124-10"
        drugMasterDAO.drugsByGtin["00312345678906"] = dashedNdcDrug

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showReplaceBottlePopup == true)
    }

    @Test func handleBottleRescanAllowedOnContainerPendingStep() {
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .containerPending
        transactionDetailDAO.totals[1] = 0
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 100, gtin: "00312345678906")

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showReplaceBottlePopup == true)
    }

    // MARK: - handleBottleRescan: duplicate vs add vs replace

    @Test func handleBottleRescanExactDuplicateTogglesNeitherPopup() {
        let transactionDAO = MockTransactionDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .scan
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 100, gtin: "00312345678906")

        // The last bottle already matches what this GS1 barcode will decode to.
        let existing = BottleInfo(lotNumber: "LOT99", expirationDate: "12-31-2027", serialNumber: "SER77", txnDetailsIds: [], scannedAt: 1)
        transactionDAO.setBottleList(txnId: 1, [existing])

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showAddBottlePopup == false)
        #expect(vm.showReplaceBottlePopup == false)
        #expect(vm.pendingBottleRescan == nil)
        // Bottle list is untouched.
        #expect(transactionDAO.getBottleList(txnId: 1) == [existing])
    }

    @Test func handleBottleRescanDifferentBottleWithPillsCountedOpensAddDialog() {
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .targetVerification
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 100, gtin: "00312345678906")

        let existing = BottleInfo(lotNumber: "OLDLOT", expirationDate: nil, serialNumber: nil, txnDetailsIds: [1], scannedAt: 1)
        transactionDAO.setBottleList(txnId: 1, [existing])
        transactionDetailDAO.totals[1] = 42 // something has been counted

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showAddBottlePopup == true)
        #expect(vm.showReplaceBottlePopup == false)
        #expect(vm.pendingBottleRescan?.lotNumber == "LOT99")
    }

    @Test func handleBottleRescanDifferentBottleWithNoPillsCountedOpensReplaceDialog() {
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .targetVerification
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 100, gtin: "00312345678906")

        let existing = BottleInfo(lotNumber: "OLDLOT", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        transactionDAO.setBottleList(txnId: 1, [existing])
        transactionDetailDAO.totals[1] = 0 // nothing counted yet

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showReplaceBottlePopup == true)
        #expect(vm.showAddBottlePopup == false)
        #expect(vm.pendingBottleRescan?.lotNumber == "LOT99")
    }

    @Test func handleBottleRescanWithEmptyBottleListAndNoPillsOpensReplaceDialog() {
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .targetVerification
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 100, gtin: "00312345678906")
        transactionDetailDAO.totals[1] = 0

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showReplaceBottlePopup == true)
    }

    // MARK: - confirm/cancel add

    @Test func confirmAddBottleAppendsAndClearsPopupState() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn

        let existing = BottleInfo(lotNumber: "OLD", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        transactionDAO.setBottleList(txnId: 1, [existing])
        let candidate = BottleInfo(lotNumber: "NEW", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 2)
        vm.pendingBottleRescan = candidate
        vm.showAddBottlePopup = true

        vm.confirmAddBottle()

        #expect(transactionDAO.getBottleList(txnId: 1) == [existing, candidate])
        #expect(vm.pendingBottleRescan == nil)
        #expect(vm.showAddBottlePopup == false)
    }

    @Test func cancelAddBottleClearsPopupStateWithoutWritingToDAO() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn

        let existing = BottleInfo(lotNumber: "OLD", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        transactionDAO.setBottleList(txnId: 1, [existing])
        vm.pendingBottleRescan = BottleInfo(lotNumber: "NEW", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 2)
        vm.showAddBottlePopup = true

        vm.cancelAddBottle()

        #expect(transactionDAO.getBottleList(txnId: 1) == [existing])
        #expect(vm.pendingBottleRescan == nil)
        #expect(vm.showAddBottlePopup == false)
    }

    // MARK: - confirm/cancel replace

    @Test func confirmReplaceBottleOverwritesLastEntryAndClearsPopupState() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn

        let existing = BottleInfo(lotNumber: "OLD", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        transactionDAO.setBottleList(txnId: 1, [existing])
        let candidate = BottleInfo(lotNumber: "NEW", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 2)
        vm.pendingBottleRescan = candidate
        vm.showReplaceBottlePopup = true

        vm.confirmReplaceBottle()

        #expect(transactionDAO.getBottleList(txnId: 1) == [candidate])
        #expect(vm.pendingBottleRescan == nil)
        #expect(vm.showReplaceBottlePopup == false)
    }

    @Test func cancelReplaceBottleClearsPopupStateWithoutWritingToDAO() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn

        let existing = BottleInfo(lotNumber: "OLD", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 1)
        transactionDAO.setBottleList(txnId: 1, [existing])
        vm.pendingBottleRescan = BottleInfo(lotNumber: "NEW", expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 2)
        vm.showReplaceBottlePopup = true

        vm.cancelReplaceBottle()

        #expect(transactionDAO.getBottleList(txnId: 1) == [existing])
        #expect(vm.pendingBottleRescan == nil)
        #expect(vm.showReplaceBottlePopup == false)
    }
}
