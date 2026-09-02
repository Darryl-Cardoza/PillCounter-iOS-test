//
//  HistoryViewModelPaginationTests.swift
//  PillCounterTests
//
//  Covers the paginated transaction fetch path added to fix History
//  freezing/lagging under a large dataset: `getTransactionsByDate` now loads
//  one bounded page via `TransactionStore.fetchByTimeRangePage` instead of
//  faulting the user's entire transaction history into memory, and
//  `loadMoreTransactionsIfNeeded` appends subsequent pages.
//

import Testing
import CoreData
@testable import PillCounter

@MainActor
struct HistoryViewModelPaginationTests {

    private func makeUser(context: NSManagedObjectContext = MockCoreData.context) -> UserEntity {
        let user = UserEntity(context: context)
        user.user_id = "test-user"
        return user
    }

    private func makeTxn(id: Int64, isDispense: Bool = true, context: NSManagedObjectContext = MockCoreData.context) -> PillCountTransactionEntity {
        let txn = PillCountTransactionEntity(context: context)
        txn.txn_id = id
        txn.is_dispense = isDispense
        txn.created_at = id
        return txn
    }

    private func makeViewModel(rows: [PillCountTransactionEntity], userId: String = "test-user") -> (HistoryViewModel, MockTransactionDataSource) {
        let userStore = MockUserDataSource()
        let user = makeUser()
        user.user_id = userId
        userStore.usersById[userId] = user

        let transactionStore = MockTransactionDataSource()
        transactionStore.timeRangeRows = rows

        let userIdProvider = StubUserIdProviding(userId: userId)

        let viewModel = HistoryViewModel(
            transactionStore: transactionStore,
            transactionDetailStore: MockTransactionDetailDataSource(),
            batchStore: MockBatchDataSource(),
            stockTxnStore: MockStockTxnDataSource(),
            bottleInfoStore: MockBottleInfoDataSource(),
            userStore: userStore,
            userIdProvider: userIdProvider
        )
        return (viewModel, transactionStore)
    }

    @Test
    func firstPageLoadsOnlyPageSizeRows() async {
        let rows = (0..<120).map { makeTxn(id: Int64($0)) }
        let (viewModel, _) = makeViewModel(rows: rows)

        await viewModel.getTransactionsByDate(startDate: Date(), endDate: Date(), filter: .fixed)

        #expect(viewModel.filteredTransactionsOfUserByDate.count == viewModel.pageSize)
        #expect(viewModel.hasMoreTransactions == true)
    }

    @Test
    func loadMoreAppendsNextPageWithoutDuplicating() async {
        let rows = (0..<120).map { makeTxn(id: Int64($0)) }
        let (viewModel, _) = makeViewModel(rows: rows)

        await viewModel.getTransactionsByDate(startDate: Date(), endDate: Date(), filter: .fixed)
        viewModel.loadMoreTransactionsIfNeeded()

        #expect(viewModel.filteredTransactionsOfUserByDate.count == viewModel.pageSize * 2)
        #expect(viewModel.hasMoreTransactions == true)

        let ids = viewModel.filteredTransactionsOfUserByDate.map(\.txn_id)
        #expect(Set(ids).count == ids.count) // no duplicates across pages
    }

    @Test
    func hasMoreBecomesFalseOnPartialLastPage() async {
        // 120 rows, page size 50 -> pages of 50, 50, 20 (short page signals end).
        let rows = (0..<120).map { makeTxn(id: Int64($0)) }
        let (viewModel, _) = makeViewModel(rows: rows)

        await viewModel.getTransactionsByDate(startDate: Date(), endDate: Date(), filter: .fixed)
        viewModel.loadMoreTransactionsIfNeeded()
        viewModel.loadMoreTransactionsIfNeeded()

        #expect(viewModel.filteredTransactionsOfUserByDate.count == 120)
        #expect(viewModel.hasMoreTransactions == false)
    }

    @Test
    func loadMoreIsNoOpOnceExhausted() async {
        let rows = (0..<10).map { makeTxn(id: Int64($0)) }
        let (viewModel, transactionStore) = makeViewModel(rows: rows)

        await viewModel.getTransactionsByDate(startDate: Date(), endDate: Date(), filter: .fixed)
        #expect(viewModel.hasMoreTransactions == false)

        let callCountBefore = transactionStore.fetchByTimeRangePageCalls.count
        viewModel.loadMoreTransactionsIfNeeded()

        #expect(transactionStore.fetchByTimeRangePageCalls.count == callCountBefore)
        #expect(viewModel.filteredTransactionsOfUserByDate.count == 10)
    }

    @Test
    func newDateSelectionResetsPagination() async {
        let rows = (0..<120).map { makeTxn(id: Int64($0)) }
        let (viewModel, _) = makeViewModel(rows: rows)

        await viewModel.getTransactionsByDate(startDate: Date(), endDate: Date(), filter: .fixed)
        viewModel.loadMoreTransactionsIfNeeded()
        #expect(viewModel.filteredTransactionsOfUserByDate.count == viewModel.pageSize * 2)

        // Re-selecting a date range must start a fresh first page, not keep appending.
        await viewModel.getTransactionsByDate(startDate: Date(), endDate: Date(), filter: .fixed)
        #expect(viewModel.filteredTransactionsOfUserByDate.count == viewModel.pageSize)
    }

    @Test
    func statusCountsStayStableAsPagesLoad() async {
        // Regression test: getStatusCounts used to read `filteredTransactionsOfUserByDate.count`
        // directly, so the "all" badge changed as more pages loaded (e.g. 50 -> 100)
        // even though nothing about the underlying data changed.
        let rows = (0..<120).map { makeTxn(id: Int64($0)) }
        let (viewModel, transactionStore) = makeViewModel(rows: rows)
        transactionStore.countByTimeRangeResult = 120

        await viewModel.getTransactionsByDate(startDate: Date(), endDate: Date(), filter: .fixed)
        let countAfterFirstPage = viewModel.getStatusCounts(for: .fixed).all

        viewModel.loadMoreTransactionsIfNeeded()
        let countAfterSecondPage = viewModel.getStatusCounts(for: .fixed).all

        #expect(countAfterFirstPage == 120)
        #expect(countAfterSecondPage == 120)
        #expect(countAfterFirstPage == countAfterSecondPage)
    }

    @Test
    func regularFilterSkipsFetchEntirely() async {
        let rows = (0..<10).map { makeTxn(id: Int64($0)) }
        let (viewModel, transactionStore) = makeViewModel(rows: rows)

        await viewModel.getTransactionsByDate(startDate: Date(), endDate: Date(), filter: .regular)

        #expect(viewModel.filteredTransactionsOfUserByDate.isEmpty)
        #expect(transactionStore.fetchByTimeRangePageCalls.isEmpty)
    }
}

/// Minimal `UserIdProviding` stub — the production type is
/// `AppStorageManager`, which reads real Keychain state and isn't
/// appropriate to touch from a unit test.
private final class StubUserIdProviding: UserIdProviding {
    var userId: String?
    init(userId: String?) { self.userId = userId }
}
