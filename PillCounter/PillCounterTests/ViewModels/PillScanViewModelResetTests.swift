//
//  PillScanViewModelResetTests.swift
//  PillCounterTests
//
//  Tests for PillScanViewModel+Reset, built with fully-mocked DAOs so no
//  CoreData access happens in this suite. `PillScanViewModel` is @MainActor.
//

import Testing
import Foundation
@testable import PillCounter

@MainActor
@Suite
struct PillScanViewModelResetTests {

    private func makeViewModel(
        transactionDAO: MockTransactionDataSource = MockTransactionDataSource(),
        transactionDetailDAO: MockTransactionDetailDataSource = MockTransactionDetailDataSource()
    ) -> PillScanViewModel {
        PillScanViewModel(
            drugMasterDAO: MockDrugCatalogDataSource(),
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

    private func makeTransaction(txnId: Int64, status: String? = CountStatus.PARTIAL.rawValue) -> PillCountTransactionEntity {
        let txn = PillCountTransactionEntity(context: MockCoreData.context)
        txn.txn_id = txnId
        txn.is_dispense = true
        txn.status = status
        return txn
    }

    // MARK: - canResetCurrentTransaction

    @Test func canResetIsTrueForPartialTransaction() {
        let vm = makeViewModel()
        vm.currentTransaction = makeTransaction(txnId: 1, status: CountStatus.PARTIAL.rawValue)
        #expect(vm.canResetCurrentTransaction == true)
    }

    @Test func canResetIsFalseForCompletedTransaction() {
        let vm = makeViewModel()
        vm.currentTransaction = makeTransaction(txnId: 1, status: CountStatus.COMPLETED.rawValue)
        #expect(vm.canResetCurrentTransaction == false)
    }

    @Test func canResetIsFalseForForceCompletedTransaction() {
        let vm = makeViewModel()
        vm.currentTransaction = makeTransaction(txnId: 1, status: CountStatus.FORCE_COMPLETED.rawValue)
        #expect(vm.canResetCurrentTransaction == false)
    }

    @Test func canResetIsFalseWithNoCurrentTransaction() {
        let vm = makeViewModel()
        #expect(vm.canResetCurrentTransaction == false)
    }

    // MARK: - resetCurrentTransaction

    @Test func resetHardDeletesDetailsAndDeletesTheirImages() {
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let vm = makeViewModel(transactionDetailDAO: transactionDetailDAO)
        let txn = makeTransaction(txnId: 42)
        vm.currentTransaction = txn
        transactionDetailDAO.hardDeleteAllImagePaths[42] = ["img1.enc", "img2.enc"]

        vm.resetCurrentTransaction()

        #expect(transactionDetailDAO.hardDeleteAllCalledWith == [42])
    }

    @Test func resetClearsNdcVerifiedFlag() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 42)
        vm.currentTransaction = txn

        vm.resetCurrentTransaction()

        #expect(transactionDAO.updateNdcVerifiedCalls.count == 1)
        #expect(transactionDAO.updateNdcVerifiedCalls.first?.txnId == 42)
        #expect(transactionDAO.updateNdcVerifiedCalls.first?.verified == false)
    }

    @Test func resetClearsPersistedWorkflowStep() {
        let transactionDAO = MockTransactionDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO)
        let txn = makeTransaction(txnId: 42)
        vm.currentTransaction = txn

        vm.resetCurrentTransaction()

        // Clears (not sets to .scan) — `.scan` is never a real persisted workflow
        // step, so writing it would make getWorkflowStep treat the transaction as
        // already resolved and skip re-deriving the real first step.
        #expect(transactionDAO.clearWorkflowStepCalls == [42])
        #expect(transactionDAO.updateWorkflowStepCalls.isEmpty)
    }

    @Test func resetDoesNotOverrideInMemoryControlledStep() {
        let vm = makeViewModel()
        let txn = makeTransaction(txnId: 42)
        vm.currentTransaction = txn
        vm.currentControlledStep = .vial

        vm.resetCurrentTransaction()

        // The screen re-derives the real step itself (via getControlledStep) once
        // the operator re-scans — resetCurrentTransaction must not force `.scan` in
        // memory, which would just be overwritten anyway and adds no value.
        #expect(vm.currentControlledStep == .vial)
    }

    @Test func resetClearsInMemoryDetailsAndTargetCount() {
        let vm = makeViewModel()
        let txn = makeTransaction(txnId: 42)
        vm.currentTransaction = txn
        vm.currentTransactionTransactionDetails = [PillCountTransactionDetailsEntity(context: MockCoreData.context)]
        vm.currentControlledTargetCount = 30

        vm.resetCurrentTransaction()

        #expect(vm.currentTransactionTransactionDetails == [])
        #expect(vm.currentControlledTargetCount == nil)
    }

    @Test func resetNoOpsWithNoCurrentTransaction() {
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO)

        vm.resetCurrentTransaction()

        #expect(transactionDetailDAO.hardDeleteAllCalledWith.isEmpty)
        #expect(transactionDAO.updateNdcVerifiedCalls.isEmpty)
        #expect(transactionDAO.clearWorkflowStepCalls.isEmpty)
    }

    @Test func resetNoOpsForCompletedTransaction() {
        let transactionDAO = MockTransactionDataSource()
        let transactionDetailDAO = MockTransactionDetailDataSource()
        let vm = makeViewModel(transactionDAO: transactionDAO, transactionDetailDAO: transactionDetailDAO)
        vm.currentTransaction = makeTransaction(txnId: 42, status: CountStatus.COMPLETED.rawValue)

        vm.resetCurrentTransaction()

        #expect(transactionDetailDAO.hardDeleteAllCalledWith.isEmpty)
        #expect(transactionDAO.updateNdcVerifiedCalls.isEmpty)
        #expect(transactionDAO.clearWorkflowStepCalls.isEmpty)
    }
}
