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
        return txn
    }

    private func makeDrug(drugId: Int64, gtin: String? = nil) -> DrugMasterEntity {
        let drug = DrugMasterEntity(context: MockCoreData.context)
        drug.drug_id = drugId
        drug.ndc = "NDC-\(drugId)"
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

    @Test func handleBottleRescanSilentlyNoOpsOnDrugIdMismatch() {
        let transactionDAO = MockTransactionDataSource()
        let drugMasterDAO = MockDrugCatalogDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, drugMasterDAO: drugMasterDAO)
        let txn = makeTransaction(txnId: 1, drugId: 100, isDispense: true)
        vm.currentTransaction = txn
        vm.currentControlledStep = .scan
        // Resolved drug exists locally but belongs to a DIFFERENT drug_id than the txn's.
        drugMasterDAO.drugsByGtin["00312345678906"] = makeDrug(drugId: 999, gtin: "00312345678906")

        vm.handleBottleRescan(rawBarcode: gs1WithFullInfo)

        #expect(vm.showAddBottlePopup == false)
        #expect(vm.showReplaceBottlePopup == false)
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
        vm.currentControlledStep = .scan
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
        vm.currentControlledStep = .scan
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
        vm.currentControlledStep = .scan
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
