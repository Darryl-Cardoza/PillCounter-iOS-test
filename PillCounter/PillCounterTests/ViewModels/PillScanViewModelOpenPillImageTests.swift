//
//  PillScanViewModelOpenPillImageTests.swift
//  PillCounterTests
//
//  Tests for PillScanViewModel.removePendingOpenBottleImage — built with fully-mocked
//  DAOs so no CoreData access happens in this suite. `PillScanViewModel` is @MainActor.
//

import Testing
import Foundation
@testable import PillCounter

@MainActor
@Suite
struct PillScanViewModelOpenPillImageTests {

    private func makeViewModel() -> PillScanViewModel {
        PillScanViewModel(
            drugMasterDAO: MockDrugCatalogDataSource(),
            transactionDAO: MockTransactionDataSource(),
            transactionDetailDAO: MockTransactionDetailDataSource(),
            batchDAO: MockBatchDataSource(),
            stockTxnDAO: MockStockTxnDataSource(),
            bottleInfoDAO: MockBottleInfoDataSource(),
            userDataLocalStorage: MockUserDataSource(),
            decoder: BarcodeAndQRDecoder(),
            userRepo: MockUserRepository(),
            controlledRepo: MockControlledRepository()
        )
    }

    /// appendOpenBottleImage hands out a monotonic id, not a timestamp — two records
    /// appended back-to-back (same or different capturedAt) must never collide.
    @Test func appendOpenBottleImageAssignsDistinctIds() {
        let vm = makeViewModel()
        vm.appendOpenBottleImage(path: "a.jpg", pillCount: 4, capturedAt: 1000, isControlled: false)
        vm.appendOpenBottleImage(path: "b.jpg", pillCount: 3, capturedAt: 1000, isControlled: false)

        let ids = vm.pendingOpenBottleImages.map { $0.id }
        #expect(Set(ids).count == 2)
    }

    /// pendingOpenBottleDbImages must carry only the controlled-drug records — the
    /// two views are derived from one array, so they can no longer desync.
    @Test func pendingOpenBottleDbImagesOnlyIncludesControlledRecords() {
        let vm = makeViewModel()
        vm.appendOpenBottleImage(path: "controlled.jpg", pillCount: 5, capturedAt: 0, isControlled: true)
        vm.appendOpenBottleImage(path: "plain.jpg", pillCount: 3, capturedAt: 1, isControlled: false)

        #expect(vm.pendingOpenBottleImages.count == 2)
        #expect(vm.pendingOpenBottleDbImages == [BottleImageRecord(path: "controlled.jpg", count: 5)])
    }

    /// Deleting a grid image must subtract that image's own pillCount from
    /// addCurrentOpenPillCount — the grid's displayed total and the loose_qty saved
    /// on Proceed — not just remove it from the record list.
    @Test func removePendingOpenBottleImageSubtractsItsPillCountFromTotal() {
        let vm = makeViewModel()
        vm.appendOpenBottleImage(path: "a.jpg", pillCount: 4, capturedAt: 0, isControlled: false)
        vm.appendOpenBottleImage(path: "b.jpg", pillCount: 3, capturedAt: 1, isControlled: false)
        vm.appendOpenBottleImage(path: "c.jpg", pillCount: 2, capturedAt: 2, isControlled: false)
        vm.addCurrentOpenPillCount = 9
        let middleId = vm.pendingOpenBottleImages[1].id

        vm.removePendingOpenBottleImage(id: middleId)

        #expect(vm.pendingOpenBottleImages.map { $0.imagePath } == ["a.jpg", "c.jpg"])
        #expect(vm.addCurrentOpenPillCount == 6)
    }

    /// Deleting the queued-for-persistence image (controlled drug) must also drop it
    /// from pendingOpenBottleDbImages, in addition to the count subtraction — a
    /// deleted image must never be saved on Proceed nor counted in the total.
    @Test func removePendingOpenBottleImageAlsoRemovesFromDbImagesAndCount() {
        let vm = makeViewModel()
        vm.appendOpenBottleImage(path: "a.jpg", pillCount: 5, capturedAt: 0, isControlled: true)
        vm.addCurrentOpenPillCount = 5
        let id = vm.pendingOpenBottleImages[0].id

        vm.removePendingOpenBottleImage(id: id)

        #expect(vm.pendingOpenBottleImages.isEmpty)
        #expect(vm.pendingOpenBottleDbImages.isEmpty)
        #expect(vm.addCurrentOpenPillCount == 0)
    }

    /// Removing an id that isn't in the list is a no-op — count must stay unchanged.
    @Test func removePendingOpenBottleImageWithUnknownIdIsNoOp() {
        let vm = makeViewModel()
        vm.appendOpenBottleImage(path: "a.jpg", pillCount: 4, capturedAt: 0, isControlled: false)
        vm.addCurrentOpenPillCount = 4

        vm.removePendingOpenBottleImage(id: 99999)

        #expect(vm.pendingOpenBottleImages.count == 1)
        #expect(vm.addCurrentOpenPillCount == 4)
    }
}
