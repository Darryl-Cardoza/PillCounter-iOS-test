//
//  PillScanViewModelSkipBackCountTests.swift
//  PillCounterTests
//
//  Tests the vial -> containerPending transition in `handleStepCompletion()`.
//  A back count with 0 remaining can never be satisfied, so the step is skipped
//  and the skip popup is surfaced instead.
//
//  Uses a real drug/transaction fixture because `PillCountingStepResolver`
//  reads `DrugCatalogStore.shared` and `AppStorageManager.shared` directly.
//

import Testing
import Foundation
@testable import PillCounter

@MainActor
@Suite
struct PillScanViewModelSkipBackCountTests {

    private func makeViewModel(
        transactionDAO: MockTransactionDataSource,
        transactionDetailDAO: MockTransactionDetailDataSource
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

    /// Controlled dispense txn sitting on `.vial`, with `containerInitiate`
    /// seeded so the back count resolves to `containerTotal - targetCount`.
    private func makeControlledFlow(
        targetCount: Int32,
        containerTotal: Int32,
        backCountRequired: Bool = true
    ) -> (
        vm: PillScanViewModel,
        txnDAO: MockTransactionDataSource,
        fixture: BottleTrackingFixture,
        previousBackCount: Bool
    ) {
        let previousBackCount = AppStorageManager.shared.isBackCountRequired
        AppStorageManager.shared.isBackCountRequired = backCountRequired

        let fixture = BottleTrackingFixture(drugType: DrugSchedule.cii.rawValue)
        let txn = fixture.makeTransaction(isDispense: true, targetCount: targetCount)

        let txnDAO = MockTransactionDataSource()
        let detailDAO = MockTransactionDetailDataSource()
        detailDAO.stepTotals[txn.txn_id] = [.containerInitiate: containerTotal]

        let vm = makeViewModel(transactionDAO: txnDAO, transactionDetailDAO: detailDAO)
        vm.currentTransaction = txn
        vm.currentControlledStep = .vial

        return (vm, txnDAO, fixture, previousBackCount)
    }

    private func tearDown(_ fixture: BottleTrackingFixture, _ previousBackCount: Bool) {
        AppStorageManager.shared.isBackCountRequired = previousBackCount
        fixture.cleanUp()
    }

    // MARK: - Back count with nothing left to scan

    @Test func skipsContainerPendingWhenNothingLeftToScan() {
        let (vm, txnDAO, fixture, previous) = makeControlledFlow(
            targetCount: 30,
            containerTotal: 30
        )
        defer { tearDown(fixture, previous) }

        vm.handleStepCompletion()

        #expect(vm.showSkipBackCountPopup == true)
        #expect(vm.currentControlledStep == .vial)
        #expect(txnDAO.updateWorkflowStepCalls.isEmpty)
    }

    @Test func advancesToContainerPendingWhenPillsRemain() {
        let (vm, txnDAO, fixture, previous) = makeControlledFlow(
            targetCount: 30,
            containerTotal: 45
        )
        defer { tearDown(fixture, previous) }

        vm.handleStepCompletion()

        #expect(vm.showSkipBackCountPopup == false)
        #expect(vm.currentControlledStep == .containerPending)
        #expect(txnDAO.updateWorkflowStepCalls.map(\.step) == [.containerPending])
    }

    // MARK: - containerPendingTarget

    @Test func containerPendingTargetIsRemainderOfContainerMinusTarget() {
        let (vm, _, fixture, previous) = makeControlledFlow(
            targetCount: 30,
            containerTotal: 45
        )
        defer { tearDown(fixture, previous) }

        #expect(vm.containerPendingTarget() == 15)
    }

    /// A container total below the dispensed target is a data inconsistency, not a
    /// negative back count — the target floors at 0, which is also a skip.
    @Test func containerPendingTargetFloorsAtZero() {
        let (vm, _, fixture, previous) = makeControlledFlow(
            targetCount: 30,
            containerTotal: 10
        )
        defer { tearDown(fixture, previous) }

        #expect(vm.containerPendingTarget() == 0)
    }

    @Test func containerPendingTargetIsZeroWithNoCurrentTransaction() {
        let vm = makeViewModel(
            transactionDAO: MockTransactionDataSource(),
            transactionDetailDAO: MockTransactionDetailDataSource()
        )
        #expect(vm.containerPendingTarget() == 0)
    }

    // MARK: - Back count disabled

    /// With back count off, `.vial` is the last step — `handleStepCompletion()`
    /// has nowhere to advance and must not raise the skip popup. The caller's
    /// `nextStep == nil` completion path owns this case.
    @Test func doesNotShowSkipPopupWhenVialIsLastStep() {
        let (vm, txnDAO, fixture, previous) = makeControlledFlow(
            targetCount: 30,
            containerTotal: 30,
            backCountRequired: false
        )
        defer { tearDown(fixture, previous) }

        vm.handleStepCompletion()

        #expect(vm.showSkipBackCountPopup == false)
        #expect(vm.currentControlledStep == .vial)
        #expect(txnDAO.updateWorkflowStepCalls.isEmpty)
    }

    // MARK: - Reset

    @Test func resetClearsSkipBackCountPopup() {
        let (vm, _, fixture, previous) = makeControlledFlow(
            targetCount: 30,
            containerTotal: 30
        )
        defer { tearDown(fixture, previous) }

        vm.showSkipBackCountPopup = true
        vm.resetCurrentTransaction()

        #expect(vm.showSkipBackCountPopup == false)
    }
}
