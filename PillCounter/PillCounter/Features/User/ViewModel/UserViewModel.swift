//
//  UserViewModel.swift
//  PillCounter
//
//  Created by HC on 12/11/25.
//

import Foundation
import SwiftUI
import CoreData

@MainActor  // decalaring this as an main actor since we will change the colors on the app launch.
class UserViewModel: ObservableObject {
    // MARK: - APP STORAGE
    let pillDataLocalStorage = PillsDataLocalStorage.shared
    // get the access token from the app storage
    @AppStorage(AppStorageManager.AppStorageKeys.accessToken) var accessToken:
        String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.refreshToken) var refreshToken:
        String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.userEmail) var userEmail:
        String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.userId) var userID: String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.pmsHostName)
    var pmsHostName: String = ""

    @AppStorage(AppStorageManager.AppStorageKeys.pillCounterHostName)
    var pillCounterHostName: String = ""


    // MARK: PUBLISHED VARIABLES
    // general loading  
    @Published var isLoading: Bool = false

    // user details
    @Published var userProfileDetails: UserProfile? = nil
    // user profile values for binding
    @Published var fullName: String = ""
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var email: String = ""
    @Published var phoneNumber: String = ""
    @Published var pharmacyName: String = ""
    @Published var npiID: String = ""

    // when user updates the profile successfully,
    @Published var isProfileUpdated: Bool = false

    // Transactions of the user.
    @Published var historyCountTransactions: [PillCountTransactionEntity] = []
    //    @Published var regularCountTransactions: [PillCountTransactionEntity] = []

    // count of fixed completed and partial
    @Published var fixedCountTransactionCompletedCount: Int = 0
    @Published var fixedCountTransactionPartialCount: Int = 0

    // count of regualr completed and partial
    @Published var regularCountTransactionCompletedCount: Int = 0
    @Published var regularCountTransactionPartialCount: Int = 0

    // transactions of the user filtered by dates.
    @Published var filteredTransactionsOfUserByDate:
        [PillCountTransactionEntity] = []

    // variable to hold the actual counted pills for the fixed transactions.
    @Published var actualCountedPillsForTheTransactions: [Int64: Int] = [:]

    // Counts for the History Header
    @Published var historyTotalTransactionsCount: Int = 0

    // this published variable is only if the user navigates to the pill count view
    @Published var currentTransactionTxnId: Int64?

    // force update
    @Published var isForceUpdate: Bool = false

    // maintenance
    @Published var isMaintenance: Bool = false
    
    @Published var unsyncedTransactions: [PillCountTransactionEntity] = []

    @Published var pmsConnectionState: PmsConnectionState = .disconnected

    // MARK: DATABASE
    // get the user db
    let userLocalDB = UserLocalDataSource.shared

    // get the pill db
    let pillLocalDB = PillsDataLocalStorage.shared

    // user repo
    let userRepo = UserRepository.shared

    // settings repo
    let settingsRepo = SettingsRepository.shared
 
    

    // MARK: MOBILE SETTINGS
    // mobile color settings.
    func loadMobileThemeSettings() {
        let appVersion =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"

        Task.detached(priority: .background) {
            do {
                let response = try await self.settingsRepo.getMobileSettings(
                    currentVersion: appVersion
                )

                await MainActor.run {
                    if let colors = response.data?.settings?.colors {
                        AppColors.shared.update(with: colors)
                    }

                    self.isMaintenance =
                        response.data?.isMaintenanceMode ?? false

                    if let iosVersion = response.data?.iosVersion {
                        self.isForceUpdate =
                            iosVersion.isVersionGreater(than: appVersion)
                    } else {
                        self.isForceUpdate = false
                    }
                    
                    self.pmsHostName = response.data?.hl7Config?.pmsHostName ?? ""
                    self.pillCounterHostName = response.data?.hl7Config?.pillCounterHostName ?? ""
                }

            } catch {
                print("❌ Failed to load mobile settings: \(error)")
                await MainActor.run {
                    self.isMaintenance = false
                    self.isForceUpdate = false
                }
            }
        }
    }

    // MARK: GET USER
    // get user info
    func getUser() async {
        
        print("UserID \(     userID)")

        isLoading = true
        
        defer { isLoading = false }
        
        if !userID.isEmpty,
           let localUser = userLocalDB.getUserByUserId(by: userID) {
            
           let name = Formatter.segregateName(from: localUser.name ?? "")
            
            // Populate UI from local DB
            firstName = name.firstName
            lastName = name.lastName
            
            email = localUser.email ?? ""
            pharmacyName = localUser.pharmacy_name ?? ""
            npiID = localUser.npi_id ?? ""
            
            getAllTransactionsAndFilterByCountType()
            
            return
        }

        do {

            // get the current statuses of the transactions
            getAllTransactionsAndFilterByCountType()

            let currentAppVersion =
                Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                as? String ?? "Unknown"

            let getUserResult = try await userRepo.getUser(
                accessToken: accessToken,
                currentAppVersion: currentAppVersion,
                fcmToken: ""  // needs to be generated on app launch. and passed in here.
            )

            if getUserResult.isSuccess ?? false {
                email = userEmail
                if let user = getUserResult.data?.profile {
                    userProfileDetails = user
                    populateEditableFields(from: user)
                }

                // save the user id to app storage.
                userID = getUserResult.data?.profile?.userId ?? ""

                // save to db only if the user that has logged in is not present.
                // condition : getting the user id from the response of the api.
                // if the user with the user id is not there in the db then save the user in db
                // else do not save the user to db. we will update the user. (using the update function of db).
                if let userId = userProfileDetails?.userId,
                    userLocalDB.getUserByUserId(by: userId) == nil
                {
                    // saved in the background thread
                    userLocalDB.saveUser(from: getUserResult)
                }

            }
            getAllTransactionsAndFilterByCountType()

        } catch let error {
            print("Error: \(error)")
        }
    }

    // private func for profile screen fields
    private func populateEditableFields(from user: UserProfile) {
        let fullName = user.fullName ?? ""
        let name = Formatter.segregateName(from: fullName)
        
        firstName = name.firstName
        lastName = name.lastName

        email = user.email ?? ""
        phoneNumber = user.phoneNumber ?? ""
        pharmacyName = user.pharmacyName ?? ""
        npiID = user.npiID ?? ""

        self.fullName = fullName
    }

    // MARK: UPDATE USER PROFILE
    // update user profile
    func updateUserProfile() async {

        if !hasUserProfileChanged() { return }

        isLoading = true

        defer { isLoading = false }

        do {

            let request = UpdateUserProfileRequest(
                fullName: "\(firstName) \(lastName)",
                pharmacyName: pharmacyName,
                phoneNumber: phoneNumber,
                npiID: npiID,
                isProfileComplete: true,
                avatarURL: "",
                notificationsEnabled: false,  // notifications permission check and accordingly update it.
                language: "",  // what should be passed in the language.
                timezone: ""  // also what should be passed in the timezone // does this means local timezone ?
            )

            let updateUserProfileResult = try await userRepo.updateUserProfile(
                request: request, accessToken: accessToken)

            if updateUserProfileResult.isSuccess ?? false {
                isProfileUpdated = true
                let previousUserProfileDetails = userProfileDetails
                userProfileDetails =
                    updateUserProfileResult.data?.profile
                    ?? previousUserProfileDetails  // fallback to what was earlier stored in user details.
            }

        } catch let error {
            print("Error: \(error)")
        }
    }

    // func to check if any updates were there in the profile.
    private func hasUserProfileChanged() -> Bool {
        guard let original = userProfileDetails else { return true }  // if no original data, treat as changed

        let originalName = original.fullName ?? ""
        let fullNameChanged = "\(firstName) \(lastName)" != originalName
        let pharmacyChanged = pharmacyName != (original.pharmacyName ?? "")
        let phoneChanged = phoneNumber != (original.phoneNumber ?? "")
        let npiChanged = npiID != (original.npiID ?? "")

        return fullNameChanged || pharmacyChanged || phoneChanged || npiChanged
    }

    // MARK: ALL TRANSACTION FILTER BY COUNT TYPE
    // get user's all active transactions.
    func getAllTransactionsAndFilterByCountType() {

        // Get the user
        guard let user = userLocalDB.getUserByUserId(by: userID) else {
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
            pillLocalDB.getAllFixedPartialTransactionsCount(for: user)

        fixedCountTransactionCompletedCount =
            pillLocalDB.getAllFixedCompletedTransactionsCount(for: user)

        // Regular count calculations
        regularCountTransactionPartialCount =
            pillLocalDB.getAllRegularPartialTransactionsCount(for: user)

        regularCountTransactionCompletedCount =
            pillLocalDB.getAllRegularCompletedTransactionsCount(for: user)
    }

    // MARK: TRANSACTION BY DATE
    // get user's transactions filtered by date.
    func getTransactionsByDate(
        startDate: Date,
        endDate: Date,
        filter: HistoryFilterType
    ) async {
        

        guard let user = userLocalDB.getUserByUserId(by: userID) else {
            print("❌ no user found in the local DB")
            self.filteredTransactionsOfUserByDate = []
            return
        }

        // MARK: Date range
        let startOfDay = Calendar.current.startOfDay(for: startDate)

         let endOfDay = Calendar.current.date(
             byAdding: DateComponents(day: 1, second: -1),
             to: Calendar.current.startOfDay(for: endDate)
         )!

        let startTimestamp = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTimestamp = Int64(endOfDay.timeIntervalSince1970 * 1000)

        // STEP 1: Get all transactions of that date
        let allTransactions =
            userLocalDB.getTransactionsForUserFilteredByDate(
                for: user,
                startDateTs: startTimestamp,
                endDateTs: endTimestamp
            )

        // STEP 2: Apply business filter
        let finalTransactions: [PillCountTransactionEntity]

        switch filter {

        case .all:
            finalTransactions = allTransactions

        case .regular:
            finalTransactions = allTransactions.filter { txn in
                txn.count_type == CountType.REGULAR.rawValue &&
                (
                    txn.status == CountStatus.COMPLETED.rawValue
                )
            }

        case .fixed:
            finalTransactions = allTransactions.filter { txn in
                txn.count_type == CountType.FIXED.rawValue &&
                (
                    txn.status == CountStatus.COMPLETED.rawValue
                )
            }
        }

        // STEP 3: assign to UI
        await MainActor.run {
            self.filteredTransactionsOfUserByDate = finalTransactions
        }
    }


    // MARK: ALL PARTIAL TRANSACTIONS
    // get user's fixed count partial transactoins
    func getAllPartialTransactions(countType: CountType) async {
        guard let user = userLocalDB.getUserByUserId(by: userID) else {
            self.historyCountTransactions = []
            return
        }

        self.historyCountTransactions =
            pillLocalDB.fetchAllTransactionFixedOrRegularPartial(
                for: user, countType: countType) ?? []

        self.actualCountedPillsForTheTransactions = [:]

        for transaction in historyCountTransactions {
            let total = pillLocalDB.getTheCountedNumberOfPillsForTheTransaction(
                for: transaction.txn_id)
            self.actualCountedPillsForTheTransactions[transaction.txn_id] =
                total
        }
    }

    // MARK: SOFT DELETE TRANSACITONS
    // func to soft delete a partular transaction.
    func softDeleteTheSelectedTransaction(
        transactionId: Int64, countType: CountType
    ) async {
        pillLocalDB.softDeleteTransaction(txnId: transactionId)

        if countType == .FIXED {
            await getAllPartialTransactions(countType: .FIXED)
        } else {
            await getAllPartialTransactions(countType: .REGULAR)
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
            pillLocalDB.softDeleteTransaction(txnId: txn.txn_id)
        }

        // Refresh UI after deletion
        await getTransactionsByDate(startDate: startDate,endDate: endDate,filter:filter)
    }

    // MARK: - FORCE COMPLETE TRANSACTION
    // func to make the transaction as force completed.
    func forceCompleteTheSelectedTransaction(txnId: Int64, countType: CountType)
        async
    {

        pillLocalDB.updateTransactionStatus(
            txnId: txnId, newStatus: .FORCE_COMPLETED)

        if countType == .FIXED {
            await getAllPartialTransactions(countType: .FIXED)
        } else {
            await getAllPartialTransactions(countType: .REGULAR)
        }
    }

    // MARK: - COMPLETE TRANSACTION
    func completeTheSelectedTransaction(
        txnId: Int64,
        countType: CountType
    ) async {
        // update the statuse
        pillLocalDB.updateTransactionStatus(
            txnId: txnId,
            newStatus: .COMPLETED
        )
        //  Refresh Partial Transactions
        if countType == .FIXED {
            await getAllPartialTransactions(countType: .FIXED)
        } else {
            await getAllPartialTransactions(countType: .REGULAR)
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
            pillLocalDB.getTransactionsForUserFilteredByTimeRange(
                for: user,
                startTime: startTs,
                endTime: endTs
            )

        // Update State
        self.filteredTransactionsOfUserByDate = transactions
        self.historyTotalTransactionsCount = transactions.count

    }

    // MARK: REFRESH TOKEN
    func refreshToken() async {
        do {
            // defer { isLoading = false } // Optional: usually background refresh doesn't show loading UI
            let refreshTokenResponse = try await userRepo.refreshToken(
                refreshToken: refreshToken)

            if refreshTokenResponse.isSuccess ?? false {

                // 1. Update Tokens
                accessToken = refreshTokenResponse.data?.accessToken ?? ""
                refreshToken = refreshTokenResponse.data?.refreshToken ?? ""

                // 2. Update Expiry Time
                let expiresInSeconds = TimeInterval(
                    refreshTokenResponse.data?.expiresIn ?? 86400)
                let newExpiryDate = Date().addingTimeInterval(expiresInSeconds)

                AppStorageManager.shared.tokenExpiryTimestamp =
                    newExpiryDate.timeIntervalSince1970
            }

        } catch let error {
            print("❌ Refresh Error: \(error)")
            // Optional: If refresh fails (e.g. 401), you might want to force logout here
        }
    }

    // MARK: - CHECK EXPIRY LOGIC
    func checkAndRefreshTokenIfNeeded() async {
        // 1. Get the stored expiry time
        let storedExpiryTimestamp =
            AppStorageManager.shared.tokenExpiryTimestamp ?? 0.0

        // If timestamp is 0, it means we haven't stored it yet (legacy login), so we should refresh just in case.
        if storedExpiryTimestamp == 0.0 {
            await refreshToken()
            return
        }
        let expiryDate = Date(timeIntervalSince1970: storedExpiryTimestamp)
        let currentDate = Date()
        // 2. Logic: Check if Current Date is AFTER Expiry Date
        // Optional: Add a "Buffer" (e.g., 5 minutes) so we refresh slightly before it actually dies.
        // If (Now > Expiry - 5 minutes) -> Refresh
        if currentDate > expiryDate.addingTimeInterval(-300) {
            await refreshToken()
        }
    }

    // MARK: - BATCH ACTIONS
    func softDeleteMultipleTransactions(
        txnIds: Set<Int64>, countType: CountType
    ) async {

        // Iterate through the set of IDs and soft delete them
        for id in txnIds {
            pillLocalDB.softDeleteTransaction(txnId: id)
        }

        // Refresh the list based on the current context
        if countType == .FIXED {
            await getAllPartialTransactions(countType: .FIXED)
        } else {
            await getAllPartialTransactions(countType: .REGULAR)
        }
    }

    // MARK: - GENERATE DUMMY DATA
    func generateDummyData() {
        let context = CoreDataManager.shared.context

        // 1. Check for Existing User OR Create Dummy User
        var user = userLocalDB.getUserByUserId(by: userID)

        if user == nil {

            let dummyUser = UserEntity(context: context)
            // Assign dummy values based on your UserEntity definition
            dummyUser.user_id = "dummy_user_123"
            dummyUser.name = "Test User"
            dummyUser.email = "test@example.com"
            dummyUser.pharmacy_name = "Test Pharmacy"
            dummyUser.phone_number = "555-0123"
            dummyUser.npi_id = "NPI-999"
            dummyUser.role = "pharmacist"
            dummyUser.is_profile_completed = true
            dummyUser.is_verified = true
            dummyUser.notifications = true
            dummyUser.language = "en"
            dummyUser.timezone = TimeZone.current.identifier
            dummyUser.created_at = Date()
            dummyUser.local_id = 1  // Arbitrary local ID since your entity requires Int64

            // Save the dummy user
            CoreDataManager.shared.save(context: context)

            // Update the ViewModel's userID so subsequent fetches work
            self.userID = dummyUser.user_id ?? ""
            user = dummyUser
        }

        guard let currentUser = user else {
            print("❌ Critical Error: Failed to retrieve or create user.")
            return
        }

        // 2. Create Dummy Drugs (So we have names to display)
        let dummyDrugs = [
            "Amoxicillin 500mg", "Ibuprofen 200mg", "Lipitor 10mg",
            "Metformin 500mg", "Lisinopril 20mg", "Amlodipine 5mg",
        ]

        var drugEntities: [DrugMasterEntity] = []

        for (i, name) in dummyDrugs.enumerated() {
            let drug = DrugMasterEntity(context: context)
            drug.drug_id = Int64(9000 + i)  // Fake IDs
            drug.drug_name = name
            drug.ndc = "00000-0000-\(i)"
            drugEntities.append(drug)
        }

        // 3. Create Dummy Transactions
        for i in 0..<10 {
            let txn = PillCountTransactionEntity(context: context)

            // Randomize Data
            let randomDrug = drugEntities.randomElement()!
            let target = Int32(Int.random(in: 30...120))
            let counted = Int32(Int.random(in: 0...Int(target)))
            let daysAgo = Int.random(in: 0...6)  // Random date in last 1 weeks

            txn.txn_id = Int64(Date().timeIntervalSince1970) + Int64(i * 1000)  // Unique-ish ID

            // Link User Relationship
            txn.user = currentUser
            txn.local_id = currentUser.local_id  // Use the Int64 local_id from the user entity
            currentUser.addToTransactions(txn)

            // Link Drug Relationship
            txn.drug = randomDrug
            txn.drug_id = randomDrug.drug_id

            // Ensure they show up in "Fixed Partial" list
            txn.count_type = CountType.FIXED.rawValue
            txn.status = CountStatus.PARTIAL.rawValue
            txn.is_deleted = false

            // Date logic
            let date = Calendar.current.date(
                byAdding: .day, value: -daysAgo, to: Date())!
            txn.created_at = Int64(date.timeIntervalSince1970 * 1000)
            txn.updated_at = txn.created_at
            txn.target_count = target

            // Add a "Detail" record so the counts (X / Y) work
            let detail = PillCountTransactionDetailsEntity(context: context)
            detail.txn_details_id = txn.txn_id + 50000
            detail.txn_id = txn.txn_id
            detail.pill_count = counted
            detail.created_at = txn.created_at
            detail.is_deleted = false
            detail.pillCountTransaction = txn
            txn.addToPillCountTransactionDetails(detail)
        }

        // 4. Save to Core Data
        CoreDataManager.shared.save(context: context)

        // 5. Refresh the list immediately
        Task {
            await getAllPartialTransactions(countType: .FIXED)
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
        return pillDataLocalStorage.fetchPillCountTransactionByTransactionId(txnId: txnId)
    }
    
    
    @MainActor
    func getUnsyncedTransactions() async {
            self.unsyncedTransactions = pillDataLocalStorage.getPendingHl7Txn()
     
    }

    
    //For showing pms connection status
    func setPmsConnected(_ isConnected: Bool) {
        pmsConnectionState = isConnected ? .connected : .disconnected
    }
    
    // MARK: - HARD RESET (called on logout)
    @MainActor
    func resetState() {
        // AppStorage backed vars
        userEmail = ""
        userID = ""
        pmsHostName = ""
        pillCounterHostName = ""

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

        // Transactions
        historyCountTransactions = []
        filteredTransactionsOfUserByDate = []
        actualCountedPillsForTheTransactions = [:]
        historyTotalTransactionsCount = 0
        currentTransactionTxnId = nil
        unsyncedTransactions = []

        fixedCountTransactionCompletedCount = 0
        fixedCountTransactionPartialCount = 0
        regularCountTransactionCompletedCount = 0
        regularCountTransactionPartialCount = 0
    }
}
