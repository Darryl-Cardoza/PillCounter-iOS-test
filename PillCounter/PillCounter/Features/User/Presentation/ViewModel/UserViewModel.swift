//
//  UserViewModel.swift
//  PillCounter
//

import Foundation
import SwiftUI
import CoreData
import ComposeApp

@MainActor
class UserViewModel: ObservableObject {

    // MARK: - Dependencies
    let pillDataLocalStorage  = PillsDataLocalStorage.shared
    let userLocalDB           = UserLocalDataSource.shared
    let pillLocalDB           = PillsDataLocalStorage.shared
    let userRepo              = UserRepository.shared
    let settingsRepo          = SettingsRepository.shared

    // MARK: - Published UI state
    @Published var isLoading: Bool = false
    @Published var userProfileDetails: UserProfile? = nil
    @Published var fullName: String = ""
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var email: String = ""
    @Published var phoneNumber: String = ""
    @Published var pharmacyName: String = ""
    @Published var npiID: String = ""
    @Published var isProfileUpdated: Bool = false
    @Published var historyCountTransactions: [PillCountTransactionEntity] = []
    @Published var fixedCountTransactionCompletedCount: Int = 0
    @Published var fixedCountTransactionPartialCount: Int = 0
    @Published var regularCountTransactionCompletedCount: Int = 0
    @Published var regularCountTransactionPartialCount: Int = 0
    @Published var filteredTransactionsOfUserByDate: [PillCountTransactionEntity] = []
    @Published var filteredBatchesOfUserByDate: [BatchCountEntity] = []
    @Published var transactionRows: [TransactionRowData] = []
    @Published var batchRows: [StockData] = []
    @Published var actualCountedPillsForTheTransactions: [Int64: Int] = [:]
    @Published var historyTotalTransactionsCount: Int = 0
    @Published var currentTransactionTxnId: Int64?
    @Published var isForceUpdate: Bool = false
    @Published var isMaintenance: Bool = false
    @Published var unsyncedTransactions: [PillCountTransactionEntity] = []
    @Published var pmsConnectionState: PmsConnectionState = .notAvailable

    // MARK: - Keychain-backed convenience
    private var accessToken: String { AppStorageManager.shared.accessToken ?? "" }

    private var userID: String {
        get { AppStorageManager.shared.userId ?? "" }
        set { AppStorageManager.shared.userId = newValue }
    }

    var bucket: [String] {
        get { AppStorageManager.shared.bucket }
        set { AppStorageManager.shared.bucket = newValue }
    }

    // MARK: - Mobile Settings

    func loadMobileThemeSettings() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        Task.detached(priority: .background) {
            do {
                let response = try await self.settingsRepo.getMobileSettings(currentVersion: appVersion)

                await MainActor.run {
                    if let colors = response.data?.settings?.colors {
                        AppColors.shared.update(with: colors)
                    }

                    self.isMaintenance = response.data?.isMaintenanceMode ?? false

                    if let iosVersion = response.data?.iosVersion {
                        self.isForceUpdate = iosVersion.isVersionGreater(than: appVersion)
                    } else {
                        self.isForceUpdate = false
                    }

                    AppStorageManager.shared.pmsHostName         = response.data?.hl7Config?.pmsHostName ?? ""
                    AppStorageManager.shared.pillCounterHostName = response.data?.hl7Config?.pillCounterHostName ?? ""
                    AppStorageManager.shared.barcodeFormat       = response.data?.hl7Config?.barcodeFormat ?? ""

                    Log("Barcode format: \(response.data?.hl7Config?.barcodeFormat ?? "")")

                    // Notify the HL7 controller that pmsHostName is now populated.
                    // This triggers the first real Bonjour browse if the service
                    // type was empty when Hl7ServiceController.evaluate() ran.
                    Hl7ServiceController.shared.notifySettingsUpdated()
                }
            } catch {
                Log("❌ Failed to load mobile settings: \(error)")
                await MainActor.run {
                    self.isMaintenance = false
                    self.isForceUpdate = false
                }
            }
        }
    }

    // MARK: - Get User

    func getUser() async {
        isLoading = true
        defer { isLoading = false }

        let currentUserID = userID

        // FIX: Only query local DB and load transactions when userID is non-empty.
        // On first launch userID is "" — querying with an empty string never finds
        // anything and floods the log with "No user found for id = ".
        if !currentUserID.isEmpty,
           let localUser = userLocalDB.getUserByUserId(by: currentUserID) {
            let name = Formatter.segregateName(from: localUser.fname ?? "")
            firstName    = name.firstName
            lastName     = name.lastName
            email        = localUser.email ?? ""
            pharmacyName = localUser.pharmacy_name ?? ""
            npiID        = localUser.npi_id ?? ""
            phoneNumber  = localUser.phone_number ?? ""
            // Load transactions only once we have a valid local user.
            getAllTransactionsAndFilterByCountType()
        }

        do {
            let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

            let result = try await userRepo.getUser(
                accessToken: accessToken,
                currentAppVersion: currentAppVersion,
                fcmToken: ""
            )

            if result.isSuccess ?? false {
                email = AppStorageManager.shared.userEmail ?? ""

                if let user = result.data?.profile {
                    userProfileDetails = user
                    populateEditableFields(from: user)
                }

                let fetchedUserId = result.data?.profile?.userId ?? ""
                if !fetchedUserId.isEmpty {
                    AppStorageManager.shared.userId = fetchedUserId
                }

                // Upsert into local DB — saveUser handles insert vs update internally.
                userLocalDB.saveUser(from: result)

                // Now that the userId is confirmed and the record is saved,
                // reload transaction counts.
                getAllTransactionsAndFilterByCountType()
            }

        } catch {
            Log("[User] Error fetching user: \(error.localizedDescription)")
        }
    }

    private func populateEditableFields(from user: UserProfile) {
        let fullName = user.fname ?? ""
        let name     = Formatter.segregateName(from: fullName)
        firstName    = name.firstName
        lastName     = name.lastName
        email        = user.email ?? ""
        phoneNumber  = user.phoneNumber ?? ""
        pharmacyName = user.pharmacyName ?? ""
        npiID        = user.npiID ?? ""
        bucket       = user.bucket
        self.fullName = fullName
    }

    // MARK: - Update User Profile

    func updateUserProfile() async {
        guard hasUserProfileChanged() else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let request = UpdateUserProfileRequest(
                fname: firstName,
                lname: lastName,
                pharmacyName: pharmacyName,
                phoneNumber: phoneNumber,
                npiID: npiID,
                isProfileComplete: true,
                avatarURL: "",
                notificationsEnabled: false,
                language: "",
                timezone: ""
            )

            // FIX: updateProfile returns UserResponse but the server may return
            // a shape where `data.profile` is at the top level of `data` rather
            // than nested under `data.user`. Decode with UserResponse as usual —
            // if the server shape genuinely differs, the parsingError will appear
            // here and you should check the 📩 API RESPONSE log block immediately
            // above this error to see the raw JSON and adjust UserResponse/UserData.
            let result = try await userRepo.updateUserProfile(
                request: request,
                accessToken: accessToken
            )

            if result.isSuccess ?? false {
                isProfileUpdated = true

                // Prefer the returned profile; fall back to current state.
                let updated = result.data?.profile ?? result.data?.user?.profile
                if let updated { userProfileDetails = updated }

                let currentUserID = userID
                if !currentUserID.isEmpty {
                    userLocalDB.updateUser(userId: currentUserID, field: .fname,        value: firstName)
                    userLocalDB.updateUser(userId: currentUserID, field: .lname,        value: lastName)
                    userLocalDB.updateUser(userId: currentUserID, field: .email,        value: email)
                    userLocalDB.updateUser(userId: currentUserID, field: .pharmacyName, value: pharmacyName)
                    userLocalDB.updateUser(userId: currentUserID, field: .phoneNumber,  value: phoneNumber)
                    userLocalDB.updateUser(userId: currentUserID, field: .npiId,        value: npiID)
                }
            }
        } catch {
            Log("updateUserProfile error: \(error)")
        }
    }

    private func hasUserProfileChanged() -> Bool {
        guard let original = userProfileDetails else { return true }
        let fullNameChanged = "\(firstName) \(lastName)" != (original.fname ?? "")
        let pharmacyChanged = pharmacyName != (original.pharmacyName ?? "")
        let phoneChanged    = phoneNumber  != (original.phoneNumber ?? "")
        let npiChanged      = npiID        != (original.npiID ?? "")
        return fullNameChanged || pharmacyChanged || phoneChanged || npiChanged
    }

    // MARK: - Transactions

    func getAllTransactionsAndFilterByCountType() {
        let currentUserID = userID

        // FIX: Guard on empty userId — avoids "No user found for id = " spam
        // before the session is loaded and before getUser() completes.
        guard !currentUserID.isEmpty else { return }

        guard let user = userLocalDB.getUserByUserId(by: currentUserID) else {
            Log("❌ [TransactionCount] User not found in local DB. UserID: \(currentUserID)")
            return
        }
        fixedCountTransactionPartialCount     = pillLocalDB.getAllFixedPartialTransactionsCount(for: user)
        fixedCountTransactionCompletedCount   = pillLocalDB.getAllFixedCompletedTransactionsCount(for: user)
        regularCountTransactionPartialCount   = pillLocalDB.getAllRegularPartialTransactionsCount(for: user)
        regularCountTransactionCompletedCount = pillLocalDB.getAllRegularCompletedTransactionsCount(for: user)
    }

    func getTransactionsByDate(startDate: Date, endDate: Date, filter: HistoryFilterType) async {
        let currentUserID = userID
        guard !currentUserID.isEmpty,
              let user = userLocalDB.getUserByUserId(by: currentUserID) else {
            filteredTransactionsOfUserByDate = []
            return
        }

        let startOfDay  = Calendar.current.startOfDay(for: startDate)
        let endOfDay    = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: endDate))!
        let startTs     = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTs       = Int64(endOfDay.timeIntervalSince1970 * 1000)

        let allTransactions = userLocalDB.getTransactionsForUserFilteredByDate(
            for: user, startDateTs: startTs, endDateTs: endTs
        )

        let finalTransactions: [PillCountTransactionEntity]
        switch filter {
        case .regular: finalTransactions = allTransactions.filter { $0.count_type == CountType.REGULAR.rawValue }
        case .fixed:   finalTransactions = allTransactions.filter { $0.count_type == CountType.FIXED.rawValue }
        }

        await MainActor.run { filteredTransactionsOfUserByDate = finalTransactions }
    }

    func getAllPartialTransactions(countType: CountType) async {
        let currentUserID = userID
        guard !currentUserID.isEmpty,
              let user = userLocalDB.getUserByUserId(by: currentUserID) else {
            historyCountTransactions = []
            return
        }
        historyCountTransactions = pillLocalDB.fetchAllTransactionFixedOrRegularPartial(for: user, countType: countType)
        actualCountedPillsForTheTransactions = [:]
        for transaction in historyCountTransactions {
            let total = pillLocalDB.getTheCountedNumberOfPillsForTheTransaction(for: transaction.txn_id)
            actualCountedPillsForTheTransactions[transaction.txn_id] = total
        }
    }

    func softDeleteTheSelectedTransaction(transactionId: Int64, countType: CountType) async {
        pillLocalDB.softDeleteTransaction(txnId: transactionId)
        if countType == .FIXED { await getAllPartialTransactions(countType: .FIXED) }
        else                   { await getAllPartialTransactions(countType: .REGULAR) }
    }

    func softDeleteTransactionsForSelectedDate(startDate: Date, endDate: Date, filter: HistoryFilterType) async {
        let toDelete = filteredTransactionsOfUserByDate
        guard !toDelete.isEmpty else { return }
        for txn in toDelete { pillLocalDB.softDeleteTransaction(txnId: txn.txn_id) }
        await getTransactionsByDate(startDate: startDate, endDate: endDate, filter: filter)
    }

    func forceCompleteTheSelectedTransaction(txnId: Int64, countType: CountType) async {
        pillLocalDB.updateTransactionStatus(txnId: txnId, newStatus: .FORCE_COMPLETED)
        if countType == .FIXED { await getAllPartialTransactions(countType: .FIXED) }
        else                   { await getAllPartialTransactions(countType: .REGULAR) }
    }

    func completeTheSelectedTransaction(txnId: Int64, countType: CountType) async {
        pillLocalDB.updateTransactionStatus(txnId: txnId, newStatus: .COMPLETED)
        if countType == .FIXED {
            await sendCompletionHL7(txnId: txnId)
            await getAllPartialTransactions(countType: .FIXED)
        } else {
            await getAllPartialTransactions(countType: .REGULAR)
        }
        getAllTransactionsAndFilterByCountType()
    }

    private func sendCompletionHL7(txnId: Int64) async {
        guard let txn = pillLocalDB.fetchPillCountTransactionByTransactionId(txnId: txnId) else {
            Log("[HL7] Txn not found")
            return
        }
        let messageId = "TXN_\(txnId)_\(Int(Date().timeIntervalSince1970))"
        let header = MessageHeaderData(
            fieldSeparator: "|", encodingCharacters: "^~\\&",
            sendingApplication: "PILLCOUNTER", sendingFacility: "PC",
            receivingApplication: "PMS", receivingFacility: "PMS",
            messageDateTime: CurrentLocalDateTime_iosKt.currentLocalDateTime(),
            messageType: "RDS", triggerEvent: "O13",
            messageControlId: messageId, processingId: "P",
            versionId: "2.3", countryCode: nil
        )
        let order = OrderData(
            orderControl: "RE", placerOrderId: "\(txnId)",
            placerOrderNamespace: nil, fillerOrderId: nil, fillerOrderNamespace: nil,
            orderStatus: "CM", orderDateTime: CurrentLocalDateTime_iosKt.currentLocalDateTime(),
            orderingProviderId: nil, orderingProviderFamilyName: nil,
            orderingProviderGivenName: nil, orderingFacility: nil
        )
        let message = CompleteHL7Message(
            messageId: messageId, messageType: "RDS", triggerEvent: "O13",
            timestamp: header.messageDateTime, sendingFacility: "PILLCOUNTER",
            header: header, patient: nil, visit: nil, order: order,
            medications: [], routes: [], components: [], dispenses: [],
            equipment: nil, inventoryItems: [], inventory: nil,
            acknowledgment: nil, notes: [], customSegments: [],
            obxSegments: [], errors: []
        )
        _ = message
    }

    // MARK: - Token Refresh

    func refreshToken() async {
        do {
            let result = try await userRepo.refreshToken(
                refreshToken: AppStorageManager.shared.refreshToken ?? ""
            )
            if result.isSuccess ?? false {
                AppStorageManager.shared.accessToken  = result.data?.accessToken ?? ""
                AppStorageManager.shared.refreshToken = result.data?.refreshToken ?? ""
                let expiresIn = TimeInterval(result.data?.expiresIn ?? 86400)
                AppStorageManager.shared.tokenExpiryTimestamp =
                    Date().addingTimeInterval(expiresIn).timeIntervalSince1970
            }
        } catch {
            Log("❌ Token refresh error: \(error)")
        }
    }

    func checkAndRefreshTokenIfNeeded() async {
        let storedExpiry = AppStorageManager.shared.tokenExpiryTimestamp ?? 0.0
        if storedExpiry == 0.0 { await refreshToken(); return }
        let expiryDate = Date(timeIntervalSince1970: storedExpiry)
        if Date() > expiryDate.addingTimeInterval(-300) { await refreshToken() }
    }

    // MARK: - Batch actions

    func softDeleteMultipleTransactions(txnIds: Set<Int64>, countType: CountType) async {
        for id in txnIds { pillLocalDB.softDeleteTransaction(txnId: id) }
        if countType == .FIXED { await getAllPartialTransactions(countType: .FIXED) }
        else                   { await getAllPartialTransactions(countType: .REGULAR) }
    }

    // MARK: - PMS connection

    func setPmsConnected(_ isConnected: Bool) {
        pmsConnectionState = isConnected ? .connected : .disconnected
    }

    func clearLocalData() { pillDataLocalStorage.clearAllLocalData() }

    func getTransactionEntity(by txnId: Int64) -> PillCountTransactionEntity? {
        guard txnId > 0 else { return nil }
        return pillDataLocalStorage.fetchPillCountTransactionByTransactionId(txnId: txnId)
    }

    func getBatchesByDate(startDate: Date, endDate: Date) async {
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay   = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: endDate))!
        let startTs    = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTs      = Int64(endOfDay.timeIntervalSince1970 * 1000)
        let batches    = pillLocalDB.getBatchesForUserFilteredByDate(startDateTs: startTs, endDateTs: endTs)
        await MainActor.run { filteredBatchesOfUserByDate = batches }
    }

    func applyFilters(status: HistoryStatusFilter, search: String, pillScanViewModel: PillScanViewModel) {
        var txns = filteredTransactionsOfUserByDate
        switch status {
        case .completed: txns = txns.filter { $0.status == CountStatus.COMPLETED.rawValue }
        case .pending:   txns = txns.filter { $0.status == CountStatus.PARTIAL.rawValue }
        case .all:       break
        }
        if !search.isEmpty {
            let q = search.lowercased()
            txns = txns.filter {
                ($0.drug?.drug_name?.lowercased() ?? "").contains(q)
                || ($0.note?.lowercased() ?? "").contains(q)
                || ($0.status?.lowercased() ?? "").contains(q)
                || ($0.drug?.ndc ?? "").contains(q)
            }
        }
        transactionRows = txns.map { txn in
            let count = pillScanViewModel.getTotalPillCountOfCurrentTransactionByType(
                type: .targetVerification,
                details: (txn.pillCountTransactionDetails?.allObjects as? [PillCountTransactionDetailsEntity] ?? []).filter { !$0.is_deleted }
            )
            return mapTransactionToRow(txn: txn, pillCount: count)
        }

        var batches = filteredBatchesOfUserByDate
        switch status {
        case .completed: batches = batches.filter { $0.status == "completed" }
        case .pending:   batches = batches.filter { $0.status == "partial" }
        case .all:       break
        }
        if !search.isEmpty {
            let q = search.lowercased()
            batches = batches.filter {
                ($0.bucket_id?.lowercased().contains(q) ?? false)
                || ($0.status?.lowercased().contains(q) ?? false)
                || String($0.batch_id).contains(q)
            }
        }
        batchRows = batches.map {
            let count = pillDataLocalStorage.getTransactionCount(for: $0.batch_id)
            return StockData(
                id: $0.batch_id, batchId: $0.batch_id, createdAt: $0.start_date_time,
                ndcCount: Int64(count), status: $0.status ?? "",
                bucketId: $0.bucket_id ?? "", isFromPms: false
            )
        }
    }

    func mapTransactionToRow(txn: PillCountTransactionEntity, pillCount: Int) -> TransactionRowData {
        TransactionRowData(
            id: String(txn.txn_id), ndc: txn.drug?.ndc ?? "",
            drugName: txn.drug?.drug_name ?? "Unknown Pill",
            createdAt: txn.created_at, barcodeImagePath: txn.barcode_image,
            pillCount: pillCount, targetCount: Int(txn.target_count),
            countType: txn.count_type ?? "", status: txn.status ?? "",
            note: txn.note, bucketId: "360B", drugType: txn.drug?.drug_type ?? ""
        )
    }

    func getStatusCounts(for type: HistoryFilterType) -> (all: Int, completed: Int, pending: Int) {
        if type == .fixed {
            let txns = filteredTransactionsOfUserByDate
            return (
                all:       txns.count,
                completed: txns.filter { $0.status == CountStatus.COMPLETED.rawValue }.count,
                pending:   txns.filter { $0.status == CountStatus.PARTIAL.rawValue }.count
            )
        } else {
            let batches = filteredBatchesOfUserByDate
            return (
                all:       batches.count,
                completed: batches.filter { $0.status == "completed" }.count,
                pending:   batches.filter { $0.status == "partial" }.count
            )
        }
    }

    // MARK: - Delete User Profile

    func deleteUserProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await userRepo.deleteUserProfile(accessToken: accessToken)
            if response.isSuccess ?? false { AppStorageManager.shared.logout() }
        } catch {
            Log("Failed to delete user profile: \(error)")
        }
    }

    // MARK: - Reset (called on logout)

    @MainActor
    func resetState() {
        isLoading                             = false
        isForceUpdate                         = false
        isMaintenance                         = false
        isProfileUpdated                      = false
        pmsConnectionState                    = .disconnected
        userProfileDetails                    = nil
        fullName                              = ""
        firstName                             = ""
        lastName                              = ""
        email                                 = ""
        phoneNumber                           = ""
        pharmacyName                          = ""
        npiID                                 = ""
        historyCountTransactions              = []
        filteredTransactionsOfUserByDate      = []
        filteredBatchesOfUserByDate           = []
        transactionRows                       = []
        batchRows                             = []
        actualCountedPillsForTheTransactions  = [:]
        historyTotalTransactionsCount         = 0
        currentTransactionTxnId               = nil
        unsyncedTransactions                  = []
        fixedCountTransactionCompletedCount   = 0
        fixedCountTransactionPartialCount     = 0
        regularCountTransactionCompletedCount = 0
        regularCountTransactionPartialCount   = 0
    }

    // MARK: - Generate Dummy Data (development only)

    func generateDummyData() {
        let context       = CoreDataManager.shared.context
        let currentUserID = userID

        var user = userLocalDB.getUserByUserId(by: currentUserID)

        if user == nil {
            let dummyUser                    = UserEntity(context: context)
            dummyUser.user_id                = "dummy_user_123"
            dummyUser.fname                  = "Test User"
            dummyUser.email                  = "test@example.com"
            dummyUser.pharmacy_name          = "Test Pharmacy"
            dummyUser.phone_number           = "555-0123"
            dummyUser.npi_id                 = "NPI-999"
            dummyUser.role                   = "pharmacist"
            dummyUser.is_profile_completed   = true
            dummyUser.is_verified            = true
            dummyUser.notifications          = true
            dummyUser.language               = "en"
            dummyUser.timezone               = TimeZone.current.identifier
            dummyUser.created_at             = Date()
            dummyUser.local_id               = 1
            CoreDataManager.shared.save(context: context)
            AppStorageManager.shared.userId  = dummyUser.user_id ?? ""
            user                             = dummyUser
        }

        guard let currentUser = user else {
            Log("❌ Critical Error: Failed to retrieve or create user.")
            return
        }

        let dummyDrugs = ["Amoxicillin 500mg","Ibuprofen 200mg","Lipitor 10mg","Metformin 500mg","Lisinopril 20mg","Amlodipine 5mg"]
        var drugEntities: [DrugMasterEntity] = []
        for (i, name) in dummyDrugs.enumerated() {
            let drug          = DrugMasterEntity(context: context)
            drug.drug_id      = Int64(9000 + i)
            drug.drug_name    = name
            drug.ndc          = "00000-0000-\(i)"
            drugEntities.append(drug)
        }

        for i in 0..<10 {
            let txn        = PillCountTransactionEntity(context: context)
            let randomDrug = drugEntities.randomElement()!
            let target     = Int32(Int.random(in: 30...120))
            let daysAgo    = Int.random(in: 0...6)
            txn.txn_id     = Int64(Date().timeIntervalSince1970) + Int64(i * 1000)
            txn.user       = currentUser
            txn.local_id   = currentUser.local_id
            currentUser.addToTransactions(txn)
            txn.drug       = randomDrug
            txn.drug_id    = randomDrug.drug_id
            txn.count_type = CountType.FIXED.rawValue
            txn.status     = CountStatus.PARTIAL.rawValue
            txn.is_deleted = false
            let date       = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
            txn.created_at = Int64(date.timeIntervalSince1970 * 1000)
            txn.updated_at = txn.created_at
            txn.target_count = target
            let detail                    = PillCountTransactionDetailsEntity(context: context)
            detail.txn_details_id         = txn.txn_id + 50000
            detail.txn_id                 = txn.txn_id
            detail.pill_count             = Int32(Int.random(in: 0...Int(target)))
            detail.created_at             = txn.created_at
            detail.is_deleted             = false
            detail.pillCountTransaction   = txn
            txn.addToPillCountTransactionDetails(detail)
        }

        CoreDataManager.shared.save(context: context)
        Task { await getAllPartialTransactions(countType: .FIXED) }
    }
}
