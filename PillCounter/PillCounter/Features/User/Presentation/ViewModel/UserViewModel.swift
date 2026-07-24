//
//  UserViewModel.swift
//  PillCounter
//

import Foundation
import SwiftUI
import CoreData

@MainActor
class UserViewModel: ObservableObject {

    // MARK: - Injected dependencies
    //
    // Default to production singletons so `UserViewModel()` keeps working;
    // tests pass mocks conforming to the data-source / repository protocols.
    let userLocalDB: UserDataSource
    let transactionDAO: TransactionDataSource
    let transactionDetailDAO: TransactionDetailDataSource
    let drugMasterDAO: DrugCatalogDataSource
    let batchDAO: BatchDataSource
    let userRepo: UserRepositoryProtocol
    let settingsRepo: SettingsRepositoryProtocol

    init(
        userLocalDB: UserDataSource = UserStore.shared,
        transactionDAO: TransactionDataSource = TransactionStore.shared,
        transactionDetailDAO: TransactionDetailDataSource = TransactionDetailStore.shared,
        drugMasterDAO: DrugCatalogDataSource = DrugCatalogStore.shared,
        batchDAO: BatchDataSource = BatchStore.shared,
        userRepo: UserRepositoryProtocol = UserRepository.shared,
        settingsRepo: SettingsRepositoryProtocol = SettingsRepository.shared
    ) {
        self.userLocalDB = userLocalDB
        self.transactionDAO = transactionDAO
        self.transactionDetailDAO = transactionDetailDAO
        self.drugMasterDAO = drugMasterDAO
        self.batchDAO = batchDAO
        self.userRepo = userRepo
        self.settingsRepo = settingsRepo
    }

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
    @Published var pharmacyTypeOptions: [PharmacyTypeOption] = []

    // terminals
    @Published var terminals: [UserTerminal] = []
    @Published var selectedTerminal: UserTerminal? = nil
    @Published var pendingTerminal: UserTerminal? = nil

    // when user updates the profile successfully,
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

    /// Loads the user.
    ///
    /// Always hydrates from the local cache (no network). The `auth/me` API is only
    /// called when `forceRemote` is true — typically right after a token refresh —
    /// or when there is no local user yet (first launch). This prevents an `auth/me`
    /// call on every screen visit; routine visits are served from local data.
    func getUser(forceRemote: Bool = false) async {
        var userID = AppStorageManager.shared.userId ?? ""
        isLoading = true
        defer {
            isLoading = false
        }

        let localUser = userID.isEmpty ? nil : userLocalDB.fetchByUserId(userID)

        if let localUser {
            firstName    = localUser.fname ?? ""
            lastName     = localUser.lname ?? ""
            // Also set fullName here. Only the remote path (populateEditableFields)
            // was setting it, so on the common cache-served dashboard visit fullName
            // stayed "" and the header's "terminal | name" line showed a blank name.
            fullName     = [localUser.fname, localUser.lname]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            email        = localUser.email ?? ""
            pharmacyName = localUser.pharmacy_name ?? ""
            npiID        = localUser.npi_id ?? ""
            phoneNumber  = localUser.phone_number ?? ""
            // Hydrate the terminal list/selection from the cached store so the
            // dropdown is populated even when we serve from local data and skip
            // the auth/me network call below.
            hydrateTerminalsFromCache()
            // Load transactions only once we have a valid local user.
            getAllTransactionsAndFilterByCountType()
        }

        // Skip the network call unless explicitly forced (e.g. after a token
        // refresh) or we have no local user to show. Serve cached data otherwise.
        guard forceRemote || localUser == nil else {
            print("👤 [getUser] Served from local cache — skipping auth/me API call")
            return
        }
        print("👤 [getUser] Calling auth/me API (forceRemote=\(forceRemote), hasLocalUser=\(localUser != nil))")

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

                if let bucket = result.data?.profile?.bucket
                    ?? result.data?.settings?.bucket
                    ?? result.data?.user?.settings?.bucket {
                    self.bucket = bucket
                }

                if let hl7Version = result.data?.settings?.hl7Version
                    ?? result.data?.user?.settings?.hl7Version {
                    AppStorageManager.shared.hl7Version = hl7Version
                }

                if let isPmsIntegrated = result.data?.settings?.isPmsIntegrated
                    ?? result.data?.user?.settings?.isPmsIntegrated {
                    AppStorageManager.shared.isPmsIntegrated = isPmsIntegrated
                }

                if let isStandalone = result.data?.settings?.isStandalone
                    ?? result.data?.user?.settings?.isStandalone {
                    AppStorageManager.shared.isStandalone = isStandalone
                }

                if let allowLocalStorage = result.data?.settings?.allowLocalStorage
                    ?? result.data?.user?.settings?.allowLocalStorage {
                    AppStorageManager.shared.allowLocalStorage = allowLocalStorage
                }

                if let bypassSSL = result.data?.settings?.bypassSSL
                    ?? result.data?.user?.settings?.bypassSSL {
                    AppStorageManager.shared.bypassSSL = bypassSSL
                }

                if let hl7MessageSpec = result.data?.settings?.hl7MessageSpec
                    ?? result.data?.user?.settings?.hl7MessageSpec {
                    AppStorageManager.shared.hl7MessageSpec = Hl7Format.fromSendingApplication(hl7MessageSpec)
                }

                AppStorageManager.shared.useStaticPMSConnection = result.data?.settings?.useStaticPMSConnection
                    ?? result.data?.user?.settings?.useStaticPMSConnection
                    ?? false

                AppStorageManager.shared.pmsIpAddress = result.data?.settings?.pmsIpAddress
                    ?? result.data?.user?.settings?.pmsIpAddress

                AppStorageManager.shared.pmsPort = result.data?.settings?.pmsPort
                    ?? result.data?.user?.settings?.pmsPort

                let fetchedTerminals = result.data?.user?.terminals
                    ?? result.data?.settings?.terminals
                    ?? []

                if !fetchedTerminals.isEmpty {
                    // Fresh data from the API — replace list, cache it locally,
                    // and always select THIS user's active terminal (don't keep
                    // a previous user's stale selection).
                    terminals = fetchedTerminals
                    AppStorageManager.shared.storedTerminals = fetchedTerminals
                    let active = fetchedTerminals.first(where: { $0.isActive == true }) ?? fetchedTerminals.first
                    selectedTerminal = active
                    pendingTerminal = active
                    AppStorageManager.shared.selectedTerminalName = active?.terminalName ?? ""
                } else {
                    // API returned no terminals — fall back to the locally cached
                    // list so the picker still works offline / on failure.
                    let cached = AppStorageManager.shared.storedTerminals
                    terminals = cached
                    if selectedTerminal == nil {
                        let active = cached.first(where: { $0.isActive == true }) ?? cached.first
                        selectedTerminal = active
                        pendingTerminal = active
                        if let name = active?.terminalName {
                            AppStorageManager.shared.selectedTerminalName = name
                        }
                    }
                }

                // Keep AppStorage in sync — verifyOTP writes userId from the auth
                // response, but getUser may return the canonical userId from the
                // profile endpoint. Ensure both agree before the CoreData lookup.
                let resolvedUserId = result.data?.profile?.userId ?? ""
                if !resolvedUserId.isEmpty {
                    userID = resolvedUserId
                    AppStorageManager.shared.userId = resolvedUserId
                }

                // Upsert — creates a new record for first-time users, updates
                // profile fields for returning users while preserving their transactions.
                userLocalDB.save(from: result)

            } else {
            }

            getAllTransactionsAndFilterByCountType()

        } catch {
            Log("[User] Error fetching user: \(error.localizedDescription)")
            // The auth/me call failed. Fall back to whatever we have cached so the
            // terminal dropdown (and profile) stay populated instead of going blank.
            if terminals.isEmpty {
                hydrateTerminalsFromCache()
            }
        }
    }

    private func populateEditableFields(from user: UserProfile) {
        firstName    = user.fname ?? ""
        lastName     = user.lname ?? ""
        email        = user.email ?? ""
        phoneNumber  = user.phoneNumber ?? ""
        pharmacyName = user.pharmacyName ?? ""
        npiID = user.npiID ?? ""
        self.bucket = user.bucket ?? ["NORMAL"]
        if let pharmacyType = user.pharmacyType {
            AppStorageManager.shared.selectedPharmacyTypeCode = pharmacyType
        }
        self.fullName = [user.fname, user.lname]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Pharmacy Types

    /// Fetches the server-driven pharmacy type list and caches it so the
    /// dropdown still has options offline / before the next fetch completes.
    func fetchPharmacyTypes() async {
        let cached = AppStorageManager.shared.pharmacyTypeOptions
        if !cached.isEmpty {
            pharmacyTypeOptions = cached
        }

        do {
            let result = try await userRepo.getPharmacyTypes(accessToken: accessToken)
            if result.isSuccess ?? false, let types = result.data?.pharmacyTypes {
                pharmacyTypeOptions = types
                AppStorageManager.shared.pharmacyTypeOptions = types
            }
        } catch {
            Log("❌ Failed to fetch pharmacy types: \(error)")
        }
    }

    // MARK: - Update User Profile

    func updateUserProfile(pharmacyTypeCode: String?) async {
        guard hasUserProfileChanged(pharmacyTypeCode: pharmacyTypeCode) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
            let trimmedLastName  = lastName.trimmingCharacters(in: .whitespaces)

            let request = UpdateUserProfileRequest(
                fname: trimmedFirstName,
                lname: trimmedLastName,
                pharmacyName: pharmacyName,
                phoneNumber: phoneNumber,
                npiID: npiID,
                isProfileComplete: true,
                avatarURL: "",
                notificationsEnabled: false,
                language: "",
                timezone: "",
                pharmacyType: pharmacyTypeCode
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

                let previousUserProfileDetails = userProfileDetails
                userProfileDetails =
                result.data?.profile
                    ?? previousUserProfileDetails
                
                if !userID.isEmpty {
                    userLocalDB.update(userId: userID, field: .fname, value: trimmedFirstName)
                    userLocalDB.update(userId: userID, field: .lname, value: trimmedLastName)
                    userLocalDB.update(userId: userID, field: .email, value: email)
                    userLocalDB.update(userId: userID, field: .pharmacyName, value: pharmacyName)
                    userLocalDB.update(userId: userID, field: .phoneNumber, value: phoneNumber)
                    userLocalDB.update(userId: userID, field: .npiId, value: npiID)
                }

                AppStorageManager.shared.selectedPharmacyTypeCode = pharmacyTypeCode
            }
        } catch {
            Log("updateUserProfile error: \(error)")
        }
    }
    // func to check if any updates were there in the profile.
    func hasProfileChanged(pharmacyTypeCode: String?) -> Bool {
        return hasUserProfileChanged(pharmacyTypeCode: pharmacyTypeCode)
    }

    private func hasUserProfileChanged(pharmacyTypeCode: String?) -> Bool {
        guard let original = userProfileDetails else { return true }  // if no original data, treat as changed

        let firstNameChanged   = firstName.trimmingCharacters(in: .whitespaces) != (original.fname ?? "")
        let lastNameChanged    = lastName.trimmingCharacters(in: .whitespaces)  != (original.lname ?? "")
        let pharmacyChanged    = pharmacyName != (original.pharmacyName ?? "")
        let phoneChanged       = phoneNumber  != (original.phoneNumber ?? "")
        let npiChanged         = npiID        != (original.npiID ?? "")
        let pharmacyTypeChanged = (pharmacyTypeCode ?? "") != (original.pharmacyType ?? "")
        return firstNameChanged || lastNameChanged || pharmacyChanged || phoneChanged || npiChanged || pharmacyTypeChanged
    }

    // MARK: - Transactions

    func getAllTransactionsAndFilterByCountType() {
        let userID = AppStorageManager.shared.userId ?? ""

        // Get the user
        guard let user = userLocalDB.fetchByUserId( userID) else {
            print(
                """
                ❌ [TransactionCount]
                User not found in local DB
                UserID: \(userID)
                """)
            return
        }

        // Fixed count calculations
        fixedCountTransactionPartialCount =
            transactionDAO.countTransactions(for: user, isDispense: true, status: .PARTIAL)

        fixedCountTransactionCompletedCount =
            transactionDAO.countTransactions(for: user, isDispense: true, status: .COMPLETED)

        // Regular count calculations
        regularCountTransactionPartialCount =
            transactionDAO.countTransactions(for: user, isDispense: false, status: .PARTIAL)

        regularCountTransactionCompletedCount =
            transactionDAO.countTransactions(for: user, isDispense: false, status: .COMPLETED)
    }

    // MARK: TRANSACTION BY DATE
    // get user's transactions filtered by date.
    func getTransactionsByDate(
        startDate: Date,
        endDate: Date,
        filter: HistoryFilterType
    ) async {
        let userID = AppStorageManager.shared.userId ?? ""

        guard let user = userLocalDB.fetchByUserId( userID) else {
            self.filteredTransactionsOfUserByDate = []
            return
        }

        let startOfDay  = Calendar.current.startOfDay(for: startDate)
        let endOfDay    = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: endDate))!
        let startTs     = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTs       = Int64(endOfDay.timeIntervalSince1970 * 1000)

        // STEP 1: Get all transactions of that date
        let allTransactions =
            userLocalDB.fetchTransactionsByDateRange(
                for: user,
                startDateTs: startTs,
                endDateTs: endTs
            )

        let finalTransactions: [PillCountTransactionEntity]
        switch filter {
        case .regular: finalTransactions = allTransactions.filter { !$0.is_dispense }
        case .fixed:   finalTransactions = allTransactions.filter { $0.is_dispense }
        }

        await MainActor.run { filteredTransactionsOfUserByDate = finalTransactions }
    }

    func getAllPartialTransactions(isDispense: Bool) async {
        guard let user = userLocalDB.fetchByUserId( userID) else {
            self.historyCountTransactions = []
            return
        }
        self.historyCountTransactions =
            transactionDAO.fetchPartial(for: user, isDispense: isDispense)

        self.actualCountedPillsForTheTransactions = [:]

        for transaction in historyCountTransactions {
            let total = transactionDetailDAO.totalCount(txnId: transaction.txn_id)
            self.actualCountedPillsForTheTransactions[transaction.txn_id] =
                total
        }
    }
    

    // MARK: SOFT DELETE TRANSACITONS
    // func to soft delete a partular transaction.
    func softDeleteTheSelectedTransaction(
        transactionId: Int64, isDispense: Bool
    ) async {
        transactionDAO.softDelete(txnId: transactionId)

        if isDispense {
            await sendCompletionHL7(txnId: transactionId)
            await getAllPartialTransactions(isDispense: true)
        } else {
            await getAllPartialTransactions(isDispense: false)
        }
        getAllTransactionsAndFilterByCountType()
    }

    /// Sends the RDS^O13 dispense-completion message for `txnId` to the connected PMS.
    /// Delegates to `Hl7ServiceController`, which builds the message via
    /// `HL7CompletionBuilder.buildCompletionMessage` (new Hl7Core DSL) and owns the
    /// send queue + retry logic.
    private func sendCompletionHL7(txnId: Int64) async {
        guard let txn = transactionDAO.fetchById(txnId) else {
            print("[HL7] Txn not found")
            return
        }
        await MainActor.run {
            Hl7ServiceController.shared.sendTransaction(txn)
        }
    }
    
    
    // MARK: - SOFT DELETE ALL TRANSACTIONS FOR A DATE
    func softDeleteTransactionsForSelectedDate(
        startDate: Date,
        endDate: Date,
        filter: HistoryFilterType
    ) async {

        let transactionsToDelete = filteredTransactionsOfUserByDate

        guard !transactionsToDelete.isEmpty else { return }

        
        for txn in transactionsToDelete {
            transactionDAO.softDelete(txnId: txn.txn_id)
        }

        // Refresh UI after deletion
        await getTransactionsByDate(startDate: startDate,endDate: endDate,filter:filter)
    }

    // MARK: - FORCE COMPLETE TRANSACTION
    // func to make the transaction as force completed.
    func forceCompleteTheSelectedTransaction(txnId: Int64, isDispense: Bool)
        async
    {
        transactionDAO.updateStatus(txnId: txnId, status: .FORCE_COMPLETED)

        if isDispense {
            await getAllPartialTransactions(isDispense: true)
        } else {
            await getAllPartialTransactions(isDispense: false)
        }
    }

    // MARK: - COMPLETE TRANSACTION
    func completeTheSelectedTransaction(
        txnId: Int64,
        isDispense: Bool
    ) async {
        // update the statuse
        transactionDAO.updateStatus(txnId: txnId, status: .COMPLETED)
        //  Refresh Partial Transactions
        if isDispense {
            await sendCompletionHL7(txnId: txnId)
            await getAllPartialTransactions(isDispense: true)
        } else {
            await getAllPartialTransactions(isDispense: false)
        }
        getAllTransactionsAndFilterByCountType()
    }

    // MARK: - HISTORY LOGIC
    /// Private helper to fetch, sort, and calculate counts
    private func fetchAndSetHistoryTransactions(
        user: UserEntity, startTs: Int64, endTs: Int64
    ) async {

        // Fetch from Local DB
        let transactions =
            transactionDAO.fetchByTimeRange(
                for: user,
                startTime: startTs,
                endTime: endTs
            )

        // Update State
        self.filteredTransactionsOfUserByDate = transactions
        self.historyTotalTransactionsCount = transactions.count

    }

    // MARK: REFRESH TOKEN

    /// Refreshes the access token if it's missing or within 5 minutes of expiry.
    /// Delegates to `SessionManager`, which shares one in-flight guard across
    /// every refresh trigger (foreground check, dashboard appear, 401 handler)
    /// so concurrent callers collapse into a single `/auth/refresh` request —
    /// this call used to fire its own independent, uncoordinated refresh.
    /// Returns `true` when a refresh was actually attempted, so callers can
    /// decide whether to re-fetch remote user data (`auth/me`) off the back of it.
    @discardableResult
    func checkAndRefreshTokenIfNeeded() async -> Bool {
        await SessionManager.shared.refreshIfNeeded()
    }

    // MARK: - BATCH ACTIONS
    func softDeleteMultipleTransactions(
        txnIds: Set<Int64>, isDispense: Bool
    ) async {

        // Iterate through the set of IDs and soft delete them
        for id in txnIds {
            transactionDAO.softDelete(txnId: id)
        }

        // Refresh the list based on the current context
        if isDispense {
            await getAllPartialTransactions(isDispense: true)
        } else {
            await getAllPartialTransactions(isDispense: false)
        }
    }

    // MARK: - DELETE USER PROFILE
    func deleteUserProfile() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await userRepo.deleteUserProfile(
                accessToken: accessToken
            )

            if response.isSuccess ?? false {
                AppStorageManager.shared.logout()
            }

        } catch {
            print("Failed to delete user profile: \(error)")
        }
    }
    
    func getTransactionEntity(by txnId: Int64) -> PillCountTransactionEntity? {
        guard txnId > 0 else { return nil }
        return transactionDAO.fetchById(txnId)
    }
    

    //For showing pms connection status
    func setPmsConnected(_ isConnected: Bool) {
        pmsConnectionState = isConnected ? .connected : .disconnected
    }
    
    func clearLocalData() {
        LocalDataCleaner.shared.clearAll()
    }

    // MARK: - UPDATE TERMINAL

    /// Populates the in-memory terminal list/selection from the locally cached
    /// store. Used when serving the profile from local data (no auth/me call),
    /// so the dropdown still shows the list and the current selection.
    func hydrateTerminalsFromCache() {
        let cached = AppStorageManager.shared.storedTerminals
        guard !cached.isEmpty else { return }
        terminals = cached

        let storedName = AppStorageManager.shared.selectedTerminalName
        let active = cached.first(where: { $0.terminalName == storedName && !storedName.isEmpty })
            ?? cached.first(where: { $0.isActive == true })
            ?? cached.first

        if selectedTerminal == nil { selectedTerminal = active }
        if pendingTerminal == nil { pendingTerminal = active }
    }

    /// UI-only selection — no API call; persisted on Save.
    func selectTerminal(_ terminal: UserTerminal) {
        pendingTerminal = terminal
    }

    func updateTerminal(_ terminal: UserTerminal) async -> Bool {
        guard let terminalId = terminal.terminalId,
              let terminalName = terminal.terminalName else { return false }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await userRepo.updateTerminal(
                terminalId: terminalId,
                terminalName: terminalName,
                isActive: true,
                accessToken: accessToken
            )
            if response.isSuccess ?? false {
                selectedTerminal = terminal
                pendingTerminal = terminal
                AppStorageManager.shared.selectedTerminalName = terminalName
                // Keep the cached list's active flag in sync with the new selection.
                terminals = terminals.map {
                    UserTerminal(
                        terminalId: $0.terminalId,
                        terminalName: $0.terminalName,
                        isActive: $0.terminalId == terminalId,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                }
                AppStorageManager.shared.storedTerminals = terminals
                return true
            }
            return false
        } catch {
            print("Failed to update terminal: \(error)")
            return false
        }
    }
    
    func getBatchesByDate(startDate: Date, endDate: Date) async {
//        guard let user = userLocalDB.fetchByUserId( userID) else {
//            await MainActor.run { self.filteredBatchesOfUserByDate = [] }
//            return
//        }

        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: endDate)
        )!

        let startTs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTs   = Int64(endOfDay.timeIntervalSince1970 * 1000)

        let batches = batchDAO.fetchByDateRange(startTs: startTs, endTs: endTs)

        await MainActor.run {
            self.filteredBatchesOfUserByDate = batches
        }
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

        
        print("Batches \(filteredBatchesOfUserByDate)")
        self.batchRows = batches.map {
        let count = batchDAO.getTransactionCount(for: $0.batch_id)
        return StockData(
                id: $0.batch_id,
                batchId: $0.batch_id,
                createdAt: $0.start_date_time,
                ndcCount: Int64(count),
                status: $0.status ?? "",
                bucketId: $0.bucket_id ?? "",
                isFromPms: false
            )
        }
    }

    func mapTransactionToRow(txn: PillCountTransactionEntity, pillCount: Int) -> TransactionRowData {
        TransactionRowData(
            id: String(txn.txn_id), ndc: txn.drug?.ndc ?? "",
            drugName: txn.drug?.drug_name ?? "Unknown Pill",
            createdAt: txn.created_at, barcodeImagePath: [BottleInfo].decode(from: txn.bottle_info_list_json).first?.barcodeImagePath,
            drugImagePath: txn.drug?.drug_image,
            pillCount: pillCount, targetCount: Int(txn.target_count),
            countType: txn.is_dispense ? "FIXED" : "REGULAR", status: txn.status ?? "",
            note: txn.note, bucketId: "360B", drugType: txn.drug?.drug_type ?? "",
            strength: txn.drug?.strength ?? "",
            dosageForm: txn.drug?.dosage_form ?? ""
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

    // MARK: - Reset (called on logout)

    @MainActor
    func resetState() {
        // AppStorage backed vars
        AppStorageManager.shared.userEmail = ""
        AppStorageManager.shared.userId = ""
        AppStorageManager.shared.pmsHostName = ""
        AppStorageManager.shared.pillCounterHostName = ""

        // Loading & flags
        isLoading = false
        isForceUpdate = false
        isMaintenance = false
        isProfileUpdated = false
        pmsConnectionState = .disconnected

        // Profile
        userProfileDetails = nil
        fullName = ""
        firstName = ""
        lastName = ""
        email = ""
        phoneNumber = ""
        pharmacyName = ""
        npiID = ""
        terminals = []
        selectedTerminal = nil
        pendingTerminal = nil
        AppStorageManager.shared.clearTerminalCache()

        // Transactions
        historyCountTransactions = []
        filteredTransactionsOfUserByDate = []
        filteredBatchesOfUserByDate = []
        
        actualCountedPillsForTheTransactions = [:]
        historyTotalTransactionsCount = 0
        currentTransactionTxnId = nil
        unsyncedTransactions = []

        fixedCountTransactionCompletedCount = 0
        fixedCountTransactionPartialCount = 0
        regularCountTransactionCompletedCount = 0
        regularCountTransactionPartialCount   = 0
    }
}


