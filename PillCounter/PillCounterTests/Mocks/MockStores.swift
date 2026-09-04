//
//  MockStores.swift
//  PillCounterTests
//
//  In-memory fakes for the DAO protocols PillScanViewModel depends on, so its
//  bottle-rescan behavior can be tested without touching CoreData at all.
//

import Foundation
import CoreData
import Combine
@testable import PillCounter

/// Private in-memory Core Data stack used ONLY to instantiate lightweight
/// `PillCountTransactionEntity` / `UserEntity` / `DrugMasterEntity` objects for
/// the mocks below — never touches the real on-disk store the app/singletons use.
enum MockCoreData {
    static let manager = CoreDataManager(inMemory: true)
    static var context: NSManagedObjectContext { manager.context }
}

// MARK: - MockTransactionDataSource

final class MockTransactionDataSource: TransactionDataSource {
    var transactionsDidChange = PassthroughSubject<Void, Never>()

    var transactions: [Int64: PillCountTransactionEntity] = [:]
    var bottleLists: [Int64: [BottleInfo]] = [:]

    /// Full ordered set `fetchByTimeRangePage` pages through, so pagination
    /// tests can script "there are N rows" without a real Core Data store.
    var timeRangeRows: [PillCountTransactionEntity] = []
    private(set) var fetchByTimeRangePageCalls: [(limit: Int, offset: Int)] = []

    func fetchById(_ txnId: Int64) -> PillCountTransactionEntity? { transactions[txnId] }
    func fetchById(_ txnId: Int64, in context: NSManagedObjectContext) -> PillCountTransactionEntity? { transactions[txnId] }
    func fetchByBatch(batchId: Int64) -> [PillCountTransactionEntity] { [] }
    func fetchByTimeRange(for user: UserEntity, startTime: Int64, endTime: Int64) -> [PillCountTransactionEntity] { timeRangeRows }
    func fetchByTimeRange(for user: UserEntity, startTime: Int64, endTime: Int64, in context: NSManagedObjectContext) -> [PillCountTransactionEntity] { timeRangeRows }
    func fetchByTimeRangePage(for user: UserEntity, startTime: Int64, endTime: Int64, limit: Int, offset: Int) -> [PillCountTransactionEntity] {
        fetchByTimeRangePageCalls.append((limit, offset))
        guard offset < timeRangeRows.count else { return [] }
        return Array(timeRangeRows[offset..<min(offset + limit, timeRangeRows.count)])
    }
    func fetchPartial(for user: UserEntity, isDispense: Bool) -> [PillCountTransactionEntity] { [] }
    func fetchPartial(for user: UserEntity, isDispense: Bool, in context: NSManagedObjectContext) -> [PillCountTransactionEntity] { [] }
    func fetchPartialPage(for user: UserEntity, isDispense: Bool, limit: Int, offset: Int) -> [PillCountTransactionEntity] { [] }
    func fetchPartialFromPms(for user: UserEntity, isDispense: Bool) -> [PillCountTransactionEntity] { [] }
    func fetchAll(for user: UserEntity) -> [PillCountTransactionEntity] { [] }
    func fetchAllPage(for user: UserEntity, limit: Int, offset: Int) -> [PillCountTransactionEntity] { [] }
    func fetchCompletedUnsynced() -> [PillCountTransactionEntity] { [] }
    func fetchCompletedUnsyncedPage(limit: Int, offset: Int) -> [PillCountTransactionEntity] { [] }
    func countCompletedUnsynced() -> Int { 0 }
    var countByTimeRangeResult: Int?
    func countByTimeRange(for user: UserEntity, startTime: Int64, endTime: Int64, status: CountStatus?) -> Int {
        countByTimeRangeResult ?? timeRangeRows.filter { status == nil || $0.status == status?.rawValue }.count
    }
    func countPendingDispense(for user: UserEntity, facet: TransactionStore.PendingDispenseFacet) -> Int { 0 }
    func fetchLatest(for user: UserEntity) -> PillCountTransactionEntity? { nil }
    func fetchAllRxNos(for user: UserEntity) -> [String] { [] }
    func fetchByRxNo(_ rxNo: String, for user: UserEntity) -> [PillCountTransactionEntity] { [] }
    func fetchDeletedByRxNo(_ rxNo: String, for user: UserEntity) -> PillCountTransactionEntity? { nil }
    func countTransactions(for user: UserEntity, isDispense: Bool, status: CountStatus) -> Int { 0 }
    func getWorkflowStep(txn: PillCountTransactionEntity) -> ControlledStep? { nil }
    func restoreDeleted(txnId: Int64) {}
    func updateStatus(txnId: Int64, status: CountStatus) {}
    func updateNote(txnId: Int64, note: String) {}
    func updateTargetCount(txnId: Int64, targetCount: Int32) {}
    func updateWorkflowStep(txnId: Int64, step: ControlledStep) {}
    func updateGlovesDetected(txnId: Int64, detected: Bool) {}
    func updateHazardousTrayDetected(txnId: Int64, detected: Bool) {}
    func updateNdcVerified(txnId: Int64, verified: Bool) {}
    func updateFromHL7Edit(txnId: Int64, drugId: Int64, targetCount: Int32, priority: String?, refillNo: String?) {}

    func getBottleList(txnId: Int64) -> [BottleInfo] {
        bottleLists[txnId] ?? []
    }

    func setBottleList(txnId: Int64, _ bottles: [BottleInfo]) {
        bottleLists[txnId] = bottles
    }

    @discardableResult
    func appendBottle(txnId: Int64, _ bottle: BottleInfo) -> [BottleInfo] {
        var bottles = getBottleList(txnId: txnId)
        bottles.append(bottle)
        bottleLists[txnId] = bottles
        return bottles
    }

    @discardableResult
    func replaceLastBottle(txnId: Int64, _ bottle: BottleInfo) -> [BottleInfo] {
        var bottles = getBottleList(txnId: txnId)
        guard !bottles.isEmpty else { return bottles }
        bottles[bottles.count - 1] = bottle
        bottleLists[txnId] = bottles
        return bottles
    }

    func create(
        for user: UserEntity, drugId: Int64?, isDispense: Bool, batchId: Int64,
        isFromPms: Bool, drugName: String?, targetCount: Int32,
        isControlled: Bool?, rxNo: String?, bucketId: String?, priority: String?,
        workFlowStep: String?, refillNo: String?
    ) -> PillCountTransactionEntity? {
        fatalError("not needed for bottle-rescan tests")
    }

    func update(
        txnId: Int64, drugId: Int64?, isDispense: Bool, targetCount: Int32?,
        substituedDrugId: Int64?, isSubstitue: Bool
    ) {}

    func softDelete(txnId: Int64) {}
}

// MARK: - MockTransactionDetailDataSource

final class MockTransactionDetailDataSource: TransactionDetailDataSource {
    /// txnId -> total non-deleted pill count, used by `totalCount(txnId:)`.
    var totals: [Int64: Int] = [:]
    var sumPillCountResult: Int = 0
    var addedDetailIds: [Int64] = []
    private var nextDetailId: Int64 = 1

    func totalCountForStep(txnId: Int64, step: ControlledStep) -> Int32 { 0 }
    func totalCountsForSteps(txnIds: [Int64], step: ControlledStep) -> [Int64: Int32] {
        Dictionary(uniqueKeysWithValues: txnIds.map { ($0, 0) })
    }
    func totalCountsForSteps(txnIds: [Int64], step: ControlledStep, in context: NSManagedObjectContext) -> [Int64: Int32] {
        Dictionary(uniqueKeysWithValues: txnIds.map { ($0, 0) })
    }

    func totalCount(txnId: Int64) -> Int {
        totals[txnId] ?? 0
    }

    @discardableResult
    func add(txnId: Int64, pillCount: Int32, imagePath: String?, type: String?, isManual: Bool) -> PillCountTransactionDetailsEntity? {
        nextDetailId += 1
        addedDetailIds.append(nextDetailId)
        return nil
    }

    func addOrReplaceVial(txnId: Int64, imagePath: String?) {}
    func fetchForStep(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity] { [] }
    func fetchAll(txnId: Int64) -> [PillCountTransactionDetailsEntity] { [] }
    func fetchAll(txnId: Int64, in context: NSManagedObjectContext) -> [PillCountTransactionDetailsEntity] { [] }
    func lastCompletedStep(txnId: Int64) -> ControlledStep? { nil }
    func softDeleteForStep(txnId: Int64, step: ControlledStep) {}
    func update(detailId: Int64, block: (PillCountTransactionDetailsEntity) -> Void) {}

    func sumPillCount(detailIds: [Int64]) -> Int {
        guard !detailIds.isEmpty else { return 0 }
        return sumPillCountResult
    }
}

// MARK: - MockBatchDataSource

final class MockBatchDataSource: BatchDataSource {
    var transactionsDidChange = PassthroughSubject<Void, Never>()
    func fetchById(_ batchId: Int64) -> BatchCountEntity? { nil }
    func fetchByDateRange(startTs: Int64, endTs: Int64) -> [BatchCountEntity] { [] }
    func fetchByDateRange(startTs: Int64, endTs: Int64, in context: NSManagedObjectContext) -> [BatchCountEntity] { [] }
    func fetchByDateRangePage(startTs: Int64, endTs: Int64, limit: Int, offset: Int) -> [BatchCountEntity] { [] }
    func fetchAllPartial() -> [BatchCountEntity] { [] }
    func fetchAllPartial(in context: NSManagedObjectContext) -> [BatchCountEntity] { [] }
    func fetchAllCompleted() -> [BatchCountEntity] { [] }
    func fetchCompletedUnsynced() -> [BatchCountEntity] { [] }
    func fetchAllPartialPage(limit: Int, offset: Int) -> [BatchCountEntity] { [] }
    func fetchAllCompletedPage(limit: Int, offset: Int) -> [BatchCountEntity] { [] }
    func fetchCompletedUnsyncedPage(limit: Int, offset: Int) -> [BatchCountEntity] { [] }
    func countCompletedUnsynced() -> Int { 0 }
    func countByDateRange(startTs: Int64, endTs: Int64, status: CountStatus?) -> Int { 0 }
    func countPendingInventory(facet: BatchStore.PendingBatchFacet) -> Int { 0 }
    func fetchLastCreated() -> BatchCountEntity? { nil }
    func getTransactionCount(for batchId: Int64) -> Int { 0 }
    func transactionCounts(for batchIds: [Int64]) -> [Int64: Int] {
        Dictionary(uniqueKeysWithValues: batchIds.map { ($0, 0) })
    }
    func transactionCounts(for batchIds: [Int64], in context: NSManagedObjectContext) -> [Int64: Int] {
        Dictionary(uniqueKeysWithValues: batchIds.map { ($0, 0) })
    }
    func create(bucketId: String, requestId: String?) -> BatchCountEntity? { nil }
    func updateStatus(batchId: Int64, status: CountStatus, completion: (() -> Void)?) {}
    func updateNote(batchId: Int64, note: String) {}
    func softDelete(ids: Set<Int64>) {}
}

// MARK: - MockStockTxnDataSource

final class MockStockTxnDataSource: StockTxnDataSource {
    var stockTxnsDidChange = PassthroughSubject<Void, Never>()
    func fetchOrCreate(batch: BatchCountEntity, drugId: Int64, bucketId: String?) -> StockTxnEntity {
        fatalError("not needed for bottle-rescan tests")
    }
    func fetchById(_ stockTxnId: Int64) -> StockTxnEntity? { nil }
    func fetchByBatch(batchId: Int64) -> [StockTxnEntity] { [] }
    func fetchByBatchAndNdc(batchId: Int64, ndc: String) -> StockTxnEntity? { nil }
    func updateStatus(stockTxnId: Int64, status: CountStatus) {}
    func softDelete(stockTxnId: Int64) {}
}

// MARK: - MockBottleInfoDataSource

final class MockBottleInfoDataSource: BottleInfoDataSource {
    var bottleInfosDidChange = PassthroughSubject<Void, Never>()
    func setSealedBottleQty(stockTxnId: Int64, bottleQty: Int32, lotNo: String?, expNo: String?) -> BottleInfoEntity? { nil }
    func sealedBottleQty(stockTxnId: Int64, lotNo: String?, expNo: String?) -> Int32 {
        let targetKey = SealedLotKey(lotNo: lotNo, expNo: expNo)
        return fetchByStockTxn(stockTxnId: stockTxnId).first { $0.isSealed && $0.sealedLotKey == targetKey }?.bottle_qty ?? 0
    }
    func addOpenedBottle(stockTxnId: Int64, looseQty: Int32, lotNo: String?, expNo: String?, serialNo: String?) -> BottleInfoEntity? { nil }
    func updateOpenedBottleLooseQty(bottleId: Int64, looseQty: Int32) {}
    func fetchById(_ bottleId: Int64) -> BottleInfoEntity? { nil }
    func fetchByStockTxn(stockTxnId: Int64) -> [BottleInfoEntity] { [] }
    func fetchByBatch(batchId: Int64) -> [BottleInfoEntity] { [] }
    func setAbsolute(bottleId: Int64, bottleQty: Int32?, looseQty: Int32?) {}
    func softDelete(bottleId: Int64) {}
}

// MARK: - MockUserDataSource

final class MockUserDataSource: UserDataSource {
    var usersById: [String: UserEntity] = [:]
    func fetchByUserId(_ userId: String) -> UserEntity? { usersById[userId] }
    func fetchTransactionsByDateRange(for user: UserEntity, startDateTs: Int64, endDateTs: Int64) -> [PillCountTransactionEntity] { [] }
    func save(from response: UserResponse) {}
    func update(userId: String, field: UserStore.UserField, value: Any?) {}
}

// MARK: - MockDrugCatalogDataSource

final class MockDrugCatalogDataSource: DrugCatalogDataSource {
    var drugsByGtin: [String: DrugMasterEntity] = [:]
    var drugsByNdc: [String: DrugMasterEntity] = [:]

    func fetchByGtin(_ gtin: String) -> DrugMasterEntity? { drugsByGtin[gtin] }
    func fetchByNdc(_ ndc: String) -> DrugMasterEntity? { drugsByNdc[ndc] }
    func fetchByNdcDigitsOnly(_ ndc: String) -> DrugMasterEntity? {
        let target = ndc.filter(\.isNumber)
        guard !target.isEmpty else { return nil }
        return drugsByNdc.first { ($0.value.ndc ?? "").filter(\.isNumber) == target }?.value
    }

    func saveManual(
        ndc: String, gtin: String, drugId: Int64, drugName: String, drugType: String?,
        strength: String?, dosageForm: String?, packageQty: Int32, isHazardous: Bool?
    ) {}

    func update(
        drugId: Int64, drugName: String?, ndc: String?, gtin: String?, drugType: String?,
        strength: String?, dosageForm: String?, packageQty: Int32?, isHazardous: Bool?
    ) {}

    @discardableResult
    func upsertFromApi(ndc: String, drugId: Int64, drug: NdcDrug, gtin: String) -> DrugMasterEntity? { nil }
}

// MARK: - MockUserRepository / MockControlledRepository

final class MockUserRepository: UserRepositoryProtocol {
    func getUser(accessToken: String, currentAppVersion: String, fcmToken: String) async throws -> UserResponse {
        fatalError("not needed for bottle-rescan tests")
    }
    func updateUserProfile(request: UpdateUserProfileRequest, accessToken: String) async throws -> UserResponse {
        fatalError("not needed for bottle-rescan tests")
    }
    func deleteUserProfile(accessToken: String) async throws -> DeleteUserResponse {
        fatalError("not needed for bottle-rescan tests")
    }
    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse {
        fatalError("not needed for bottle-rescan tests")
    }
    func updateTerminal(terminalId: String, terminalName: String, isActive: Bool, deviceKey: String, accessToken: String) async throws -> UpdateTerminalResponse {
        fatalError("not needed for bottle-rescan tests")
    }
    func getTerminals(availableOnly: Bool, deviceKey: String, accessToken: String) async throws -> TerminalListResponse {
        fatalError("not needed for bottle-rescan tests")
    }
    func getPharmacyTypes(accessToken: String) async throws -> PharmacyTypeResponse {
        fatalError("not needed for bottle-rescan tests")
    }
    func getCountries(accessToken: String) async throws -> CountryResponse {
        fatalError("not needed for bottle-rescan tests")
    }
}

final class MockControlledRepository: ControlledRepositoryProtocol {
    func getControlledDrugInfo(ndcValidationRequest: NdcValidationRequest) async throws -> NdcComparisonResponse {
        fatalError("not needed for bottle-rescan tests")
    }
}

// MARK: - MockTerminalUserRepository

/// Controllable fake for the terminal claim/release flow (`UserViewModel.updateTerminal`,
/// `loadTerminals`). Separate from `MockUserRepository` above, which fatalErrors on every
/// method — this one lets tests script `getTerminals`/`updateTerminal` responses and errors.
final class MockTerminalUserRepository: UserRepositoryProtocol {
    var getTerminalsResults: [Result<TerminalListResponse, Error>] = []
    var updateTerminalResults: [Result<UpdateTerminalResponse, Error>] = []
    var updateUserProfileResult: Result<UserResponse, Error>?
    var getCountriesResult: Result<CountryResponse, Error>?

    private(set) var getTerminalsCallCount = 0
    private(set) var updateTerminalCallCount = 0
    private(set) var getCountriesCallCount = 0
    private(set) var lastUpdateTerminalDeviceKey: String?
    private(set) var lastUpdateUserProfileRequest: UpdateUserProfileRequest?

    func getUser(accessToken: String, currentAppVersion: String, fcmToken: String) async throws -> UserResponse {
        fatalError("not used by terminal-flow tests")
    }
    func updateUserProfile(request: UpdateUserProfileRequest, accessToken: String) async throws -> UserResponse {
        lastUpdateUserProfileRequest = request
        guard let result = updateUserProfileResult else {
            fatalError("updateUserProfile called but no result was scripted")
        }
        return try result.get()
    }
    func deleteUserProfile(accessToken: String) async throws -> DeleteUserResponse {
        fatalError("not used by terminal-flow tests")
    }
    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse {
        fatalError("not used by terminal-flow tests")
    }
    func getPharmacyTypes(accessToken: String) async throws -> PharmacyTypeResponse {
        fatalError("not used by terminal-flow tests")
    }

    func getCountries(accessToken: String) async throws -> CountryResponse {
        getCountriesCallCount += 1
        guard let result = getCountriesResult else {
            fatalError("getCountries called but no result was scripted")
        }
        return try result.get()
    }

    func getTerminals(availableOnly: Bool, deviceKey: String, accessToken: String) async throws -> TerminalListResponse {
        let index = getTerminalsCallCount
        getTerminalsCallCount += 1
        guard index < getTerminalsResults.count else {
            fatalError("getTerminals called \(getTerminalsCallCount) times but only \(getTerminalsResults.count) results were scripted")
        }
        return try getTerminalsResults[index].get()
    }

    func updateTerminal(terminalId: String, terminalName: String, isActive: Bool, deviceKey: String, accessToken: String) async throws -> UpdateTerminalResponse {
        let index = updateTerminalCallCount
        updateTerminalCallCount += 1
        lastUpdateTerminalDeviceKey = deviceKey
        guard index < updateTerminalResults.count else {
            fatalError("updateTerminal called \(updateTerminalCallCount) times but only \(updateTerminalResults.count) results were scripted")
        }
        return try updateTerminalResults[index].get()
    }
}

enum MockRepositoryError: Error {
    case generic
}
