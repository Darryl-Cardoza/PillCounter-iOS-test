//
//  PillsDataLocalStorage.swift
//  PillCounter
//
//  Created by HC on 17/11/25.
//

import CoreData

final class PillsDataLocalStorage {

    // singleton instance
    static let shared = PillsDataLocalStorage()

     var pendingTxnController: NSFetchedResultsController<PillCountTransactionEntity>?
    
    
    
    // init function.
    private init() {}

    // MARK: DRUG MASTER
    // context that we need to save the operations or find something.
    let mainThreadContext = CoreDataManager.shared.context

    // background context
    //    private let backgroundContext = CoreDataManager.shared.backgroundContext

    // save pill the drug master entity — upsert by ndc
    func savePill(from response: GetDrugResponse, ndc: String, drugId: Int64) {

        guard let pillData = response.data else {
            print("❌ No pill data found.")
            return
        }

        let entity = fetchOrCreateDrug(ndc: ndc, drugId: drugId)
        entity.drug_name = pillData.genericName
        entity.drug_type = ""
        entity.ndc = ndc

        CoreDataManager.shared.save(context: mainThreadContext)
    }

    // save manual pill — upsert by ndc
    func saveManualPill(
        ndc: String,
        gtin: String = "",
        drugId: Int64,
        drugName: String,
        drugType: String = "",
        packageQty: Int32 = 0
    ) {
        let entity = fetchOrCreateDrug(ndc: ndc, drugId: drugId)

        if entity.drug_name == nil || entity.drug_name!.isEmpty {
            entity.drug_name = drugName
        }
        if !gtin.isEmpty { entity.gtin = gtin }
        if let drugType { entity.drug_type = drugType }
        if packageQty > 0 { entity.package_qty = packageQty }
        entity.ndc = ndc

        CoreDataManager.shared.save(context: mainThreadContext)
    }

    /// Fetch existing DrugMasterEntity by ndc, or create a new one.
    /// Uses ndc as the unique key — prevents duplicate rows across flows.
    @discardableResult
    func fetchOrCreateDrug(ndc: String, drugId: Int64) -> DrugMasterEntity {
        if let existing = getPillByNdc(by: ndc) {
            return existing
        }
        let entity = DrugMasterEntity(context: mainThreadContext)
        entity.drug_id = drugId
        entity.created_at = Int64(Date().timeIntervalSince1970 * 1000)
        entity.drug_name = drugName
        entity.ndc = ndc
        entity.gtin = gtin
        entity.drug_type = drugType
        entity.package_qty = packageQty

    /// Remove duplicate DrugMasterEntity rows that share the same ndc,
    /// keeping only the first (oldest created_at).
    func deduplicateDrugMaster() {
        let all = getAllPills()
        var seen: [String: DrugMasterEntity] = [:]
        for drug in all {
            let key = drug.ndc ?? ""
            if key.isEmpty { continue }
            if let existing = seen[key] {
                if drug.created_at < existing.created_at {
                    mainThreadContext.delete(existing)
                    seen[key] = drug
                } else {
                    mainThreadContext.delete(drug)
                }
            } else {
                seen[key] = drug
            }
        }
        CoreDataManager.shared.save(context: mainThreadContext)
    }


    func getPillByNdc(by ndc: String) -> DrugMasterEntity? {

        let request: NSFetchRequest<DrugMasterEntity> =
            DrugMasterEntity.fetchRequest()
        request.predicate = NSPredicate(format: "ndc == %@", ndc)
        request.fetchLimit = 1

        return try? mainThreadContext.fetch(request).first
    }
    
    func getPillByGtin(by gtin: String) -> DrugMasterEntity? {

        let request: NSFetchRequest<DrugMasterEntity> =
            DrugMasterEntity.fetchRequest()
        request.predicate = NSPredicate(format: "gtin == %@", gtin)
        request.fetchLimit = 1

        return try? mainThreadContext.fetch(request).first
    }

    // func to get all pills. -- admin side functionality.
    func getAllPills() -> [DrugMasterEntity] {
        let request: NSFetchRequest<DrugMasterEntity> =
            DrugMasterEntity.fetchRequest()
        return (try? mainThreadContext.fetch(request)) ?? []
    }

    // fetch drug from the db by id.
    func fetchDrugById(_ drugId: Int64) -> DrugMasterEntity? {
        let request: NSFetchRequest<DrugMasterEntity> =
            DrugMasterEntity.fetchRequest()
        request.predicate = NSPredicate(format: "drug_id == %lld", drugId)
        request.fetchLimit = 1
        return try? mainThreadContext.fetch(request).first
    }

    // MARK: PILL COUNT TRANSACTION
    // create transaction for the pill after scanning the qr or barcode.
    func createTransaction(
        for user: UserEntity,
        drugId: Int64?,
        countType: CountType,
        batchId: Int64? = nil,
        barcodeImagePath: String,
        isComingFromPms: Bool? = nil,
        drugName:String? = nil,
        targetCount: Int32? = nil,
        isControlled: Bool? = nil,
        expirationDate: String? = nil,
        lotNumber: String? = nil
    ) {
        let entity = PillCountTransactionEntity(context: mainThreadContext)

        entity.txn_id = generateUniqueTransactionId()  // generate new transaction id for each new transaction.
        // local_id -> current_user_id
        entity.local_id = Int64(AppStorageManager.shared.userId ?? "") ?? 0
        // drug_id -> this is for which drug we are creating the transaction for.
        entity.drug_id = drugId ?? 0

        entity.batch_id = batchId ?? 0
        entity.rx_no = rxNo
        // relation ship.
        // ONE DRUG --> MULTIPLE TRANSACTION --> THIS LINKS THE CREATED TRANSACTION TO THAT DRUG.
        if let drugId = drugId, let drugEntity = fetchDrugById(drugId) {
            entity.drug = drugEntity
            drugEntity.addToTransactions(entity)
        }

        entity.count_type = countType.rawValue  // either fixed or regular.
        entity.status = CountStatus.PARTIAL.rawValue  // by default status of each created transaction will be partial which means pending.

        // by default value for target_count will be set to null.
        entity.is_deleted = false

        // barcode image path.
        entity.barcode_image = barcodeImagePath

        // setting both the values created_at and updated_at same at time of creating the transaction.
        entity.created_at = Int64(Date().timeIntervalSince1970 * 1000)
        entity.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        
        // set is hl7 or normal transaction and isSynced false
        entity.is_from_pms = isComingFromPms ?? false
        entity.is_synced = false
    
        entity.target_count = targetCount ?? 0
        entity.is_ndc_verfied = false
        entity.user = user
      
        entity.expiry = expirationDate
        entity.lot_no = lotNumber
        // finally save the transaction in core data.
        CoreDataManager.shared.save(context: mainThreadContext)
        debugPrintAllTransactions()
        debugPrintFullDatabase()
    }

    // fetch pill count transaction.
    func fetchPillCountTransactionByTransactionId(txnId: Int64)
        -> PillCountTransactionEntity?
    {

        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld", txnId)
        request.fetchLimit = 1

        return try? mainThreadContext.fetch(request).first
    }

//    // update the status of the particular transaction
//    func updateTransactionStatus(txnId: Int64, newStatus: CountStatus) {
//        // fetch from the db that particular transaction.
//        guard
//            let transaction = fetchPillCountTransactionByTransactionId(
//                txnId: txnId)
//        else {
//            print("❌ no transaction found.")
//            return
//        }
//
//        transaction.status = newStatus.rawValue
//        transaction.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
//        CoreDataManager.shared.save(context: mainThreadContext)
//    }

    // function to update or insert note.
    func updateNote(txnId: Int64, note: String) {

        guard
            let transaction = fetchPillCountTransactionByTransactionId(
                txnId: txnId)
        else {
            print("❌ no transaction found.")
            return
        }

        transaction.note = note
        transaction.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)

    }

    func fetchTransactionById(txnId: String) -> PillCountTransactionEntity? {
         let request: NSFetchRequest<PillCountTransactionEntity> =
             PillCountTransactionEntity.fetchRequest()
         request.predicate = NSPredicate(
             format: "txn_id == %@ AND is_deleted == false", txnId
         )
         request.fetchLimit = 1
         return try? mainThreadContext.fetch(request).first
     }
    
    // function to update the target count.
    func updateTargetCount(txnId: Int64, targetCount: Int32) {

        guard
            let transaction = fetchPillCountTransactionByTransactionId(
                txnId: txnId)
        else {
            print("❌ no transaction found.")
            return
        }

        transaction.target_count = targetCount
        transaction.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)

    }

    // soft delete the transaction
    func softDeleteTransaction(txnId: Int64) {

        print("➡️ DB Delete Request for txnId:", txnId)

        guard let transaction = fetchPillCountTransactionByTransactionId(txnId: txnId) else {
            print("❌ DB ERROR: no transaction found for id \(txnId)")
            return
        }


        transaction.is_deleted = true
        transaction.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)

    }

    // get all fixed partial count
    func getAllFixedPartialTransactionsCount(for user: UserEntity) -> Int {
        let request: NSFetchRequest<NSNumber> = NSFetchRequest(
            entityName: "PillCountTransactionEntity")
        request.resultType = .countResultType

        request.predicate = NSPredicate(
            format:
                "user == %@ AND count_type == %@ AND status == %@ AND is_deleted == false",
            user, CountType.FIXED.rawValue, CountStatus.PARTIAL.rawValue
        )

        return (try? mainThreadContext.count(for: request)) ?? 0
    }

    // get all fixed completed count
    func getAllFixedCompletedTransactionsCount(for user: UserEntity) -> Int {
        let request: NSFetchRequest<NSNumber> = NSFetchRequest(
            entityName: "PillCountTransactionEntity")
        request.resultType = .countResultType

        request.predicate = NSPredicate(
            format:
                "user == %@ AND count_type == %@ AND status IN %@ AND is_deleted == false",
            user,
            CountType.FIXED.rawValue,
            [
                CountStatus.COMPLETED.rawValue,
            ]
        )

        return (try? mainThreadContext.count(for: request)) ?? 0
    }

    // get all regular partial count
    func getAllRegularPartialTransactionsCount(for user: UserEntity) -> Int {
        let request: NSFetchRequest<NSNumber> = NSFetchRequest(
            entityName: "PillCountTransactionEntity")
        request.resultType = .countResultType

        request.predicate = NSPredicate(
            format:
                "user == %@ AND count_type == %@ AND status == %@ AND is_deleted == false",
            user, CountType.REGULAR.rawValue, CountStatus.PARTIAL.rawValue
        )

        return (try? mainThreadContext.count(for: request)) ?? 0
    }

    // get all regular completed count.
    func getAllRegularCompletedTransactionsCount(for user: UserEntity) -> Int {
        let request: NSFetchRequest<NSNumber> = NSFetchRequest(
            entityName: "PillCountTransactionEntity")
        request.resultType = .countResultType

        request.predicate = NSPredicate(
            format:
                "user == %@ AND count_type == %@ AND status IN %@ AND is_deleted == false",
            user,
            CountType.REGULAR.rawValue,
            [
                CountStatus.COMPLETED.rawValue,
            ]
        )


        return (try? mainThreadContext.count(for: request)) ?? 0
    }

    // fetch the latest transaction
    func fetechLatestTransactionOfUser(for user: UserEntity)
        -> PillCountTransactionEntity?
    {
        // make the fetch request
        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", user)
        request.sortDescriptors = [
            NSSortDescriptor(key: "created_at", ascending: false)
        ]
        request.fetchLimit = 1

        return try? mainThreadContext.fetch(request).first
    }

    // fetch all the transaction fixed partial only.
    func fetchAllTransactionFixedOrRegularPartial(
        for user: UserEntity,
        countType: CountType
    ) -> [PillCountTransactionEntity] {

        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND count_type == %@ AND status == %@",
            user,
            countType.rawValue,
            CountStatus.PARTIAL.rawValue
        )

        request.sortDescriptors = [
            NSSortDescriptor(key: "is_from_pms", ascending: false),
            NSSortDescriptor(key: "created_at", ascending: false)
        ]

        return (try? mainThreadContext.fetch(request)) ?? []
    }
    
    func fetchAllTransactionFixedOrRegularPartialFromPms(
        for user: UserEntity,
        countType: CountType
    ) -> [PillCountTransactionEntity] {

        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND count_type == %@ AND status == %@ AND is_from_pms == true",
            user,
            countType.rawValue,
            CountStatus.PARTIAL.rawValue
        )

        request.sortDescriptors = [
            NSSortDescriptor(key: "is_from_pms", ascending: false),
            NSSortDescriptor(key: "created_at", ascending: false)
        ]

        return (try? mainThreadContext.fetch(request)) ?? []
    }

    private func generateUniqueTransactionId() -> Int64 {
        let key = "txnTransactionIdCounter"
        let defaults = UserDefaults.standard
        let current = defaults.integer(forKey: key)
        let newId = current + 1
        defaults.set(newId, forKey: key)
        return Int64(newId)
    }

    // MARK: PILL COUNT TRANSACTION DETIAL

    // func to create pill count transaction detail for a particular transaction id. ( this transaction id could be mapped to PillCountTransactionEntity
    func addTransactionDetail(
        txnId: Int64,
        pillCount: Int32?,
        imagePath: String? = nil,
        type: String? = nil,
        isManual: Bool = false
    ) {

        // parent table
        // pill count transaction entity
        guard
            let parentTransactionDetialEntity =
                fetchPillCountTransactionByTransactionId(txnId: txnId)
        else {
            print("❌ no transaction found for the parent.")
            return
        }

        // create a new pill count transaction detial entity.
        let pillCountTransactionDetail = PillCountTransactionDetailsEntity(
            context: mainThreadContext)

        // add the details in the transaction detail.
        pillCountTransactionDetail.txn_details_id = generateUniqueDetailId()
        pillCountTransactionDetail.txn_id = txnId
        pillCountTransactionDetail.pill_count = pillCount ?? 0
        pillCountTransactionDetail.image_path = imagePath
        pillCountTransactionDetail.type = type
        pillCountTransactionDetail.is_manual = isManual
        pillCountTransactionDetail.is_deleted = false
        pillCountTransactionDetail.created_at = Int64(
            Date().timeIntervalSince1970 * 1000)
        pillCountTransactionDetail.updated_at =
            pillCountTransactionDetail.created_at

        // relationship manager.
        pillCountTransactionDetail.pillCountTransaction =
            parentTransactionDetialEntity
        // this is to add this added transaction detail to that particular transaction.
        parentTransactionDetialEntity.addToPillCountTransactionDetails(
            pillCountTransactionDetail)

        CoreDataManager.shared.save(context: mainThreadContext)
    }

    // fetch a particular transaction details of a transaction id.
    func getTransactionDetailsByTransactionId(txnId: Int64)
        -> [PillCountTransactionDetailsEntity]
    {

        let request: NSFetchRequest<PillCountTransactionDetailsEntity> =
            PillCountTransactionDetailsEntity.fetchRequest()

        // match the transaction id.
        request.predicate = NSPredicate(
            format: "txn_id == %lld AND is_deleted == false", txnId)

        // sort the list.
        request.sortDescriptors = [
            NSSortDescriptor(key: "created_at", ascending: true)
        ]

        return (try? mainThreadContext.fetch(request)) ?? []
    }

    // fetch transaction detail by id
    func fetchPillCountTransactionDetailById(txnDetailId: Int64)
        -> PillCountTransactionDetailsEntity?
    {

        let request: NSFetchRequest<PillCountTransactionDetailsEntity> =
            PillCountTransactionDetailsEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "txn_details_id == %lld", txnDetailId)
        request.fetchLimit = 1

        return try? mainThreadContext.fetch(request).first
    }

    // update a particular transaction detail
    func updatePillCountTransactionDetailById(
        txnDetailId: Int64,
        updateBlock: (PillCountTransactionDetailsEntity) -> Void
    ) {

        guard
            let detail = fetchPillCountTransactionDetailById(
                txnDetailId: txnDetailId)
        else {
            print("❌ No transaction detail found for id: \(txnDetailId)")
            return
        }

        updateBlock(detail)  // from this you can update any feild.
        detail.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)
    }

    private func generateUniqueDetailId() -> Int64 {
        let key = "txnDetailIdCounter"
        let defaults = UserDefaults.standard
        let current = defaults.integer(forKey: key)
        let newId = current + 1
        defaults.set(newId, forKey: key)
        return Int64(newId)
    }

    // this for the count History view to get the actual counted value of the pills of the feteched transactions.
    func getTheCountedNumberOfPillsForTheTransaction(for txnId: Int64) -> Int {
        let result = getTransactionDetailsByTransactionId(txnId: txnId)

        return result.reduce(0) { $0 + Int($1.pill_count) }
    }

    // MARK: - HISTORY CLEANUP
    /// Deletes transactions older than the selected history option.
    /// Also removes associated images from the Document Directory.
    func cleanUpOldHistory() {
        let selectedOption = AppStorageManager.shared.saveHistoryOption

        // 1. Calculate Cutoff Timestamp
        guard let cutoffDate = selectedOption.getCutoffDate() else { return }
        let cutoffTimestamp = Int64(cutoffDate.timeIntervalSince1970 * 1000)

        // 2. Fetch Request
        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()
        // Predicate: created_at < cutoffTimestamp
        request.predicate = NSPredicate(
            format: "created_at < %lld", cutoffTimestamp)

        do {
            let oldTransactions = try mainThreadContext.fetch(request)

            if oldTransactions.isEmpty {
                return
            }

            // 3. Iterate and Delete
            for transaction in oldTransactions {

                // A. Delete Transaction Barcode Image
                if let barcodePath = transaction.barcode_image {
                    deleteFileFromDocuments(fileName: barcodePath)
                }

                // B. Delete Detail Images
                if let details = transaction.pillCountTransactionDetails
                    as? Set<PillCountTransactionDetailsEntity>
                {
                    for detail in details {
                        if let detailImagePath = detail.image_path {
                            deleteFileFromDocuments(fileName: detailImagePath)
                        }
                    }
                }

                // C. Delete the Entity from Core Data
                // Note: If your relationship is set to "Cascade", deleting the transaction
                // will automatically delete the details entities.
                mainThreadContext.delete(transaction)
            }

            // 4. Save Changes
            CoreDataManager.shared.save(context: mainThreadContext)
            print(
                "🗑️ Cleanup Complete: Deleted \(oldTransactions.count) expired transactions."
            )

        } catch {
            print("❌ Error cleaning up history: \(error.localizedDescription)")
        }
    }

    /// Helper to remove actual files from disk
    private func deleteFileFromDocuments(fileName: String) {
        // Handle cases where the path might be a full URL or just a filename
        let fileManager = FileManager.default

        // Get Document Directory
        guard
            let documentsUrl = fileManager.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else { return }

        // If the fileName is just a name (e.g., "img123.jpg"), append it to doc path
        // If it is already a full path, use it directly (logic depends on how you saved it)
        let fileUrl = documentsUrl.appendingPathComponent(
            (fileName as NSString).lastPathComponent)

        if fileManager.fileExists(atPath: fileUrl.path) {
            try? fileManager.removeItem(at: fileUrl)
            print("   - Deleted file: \(fileName)")
        }
    }
    
    // MARK: - FETCH TRANSACTIONS
    
    /// Fetches transactions for a user within a specific time range (timestamps in milliseconds).
    /// Used for both "History Option" range and "Single Date" range.
    func getTransactionsForUserFilteredByTimeRange(
        for user: UserEntity,
        startTime: Int64,
        endTime: Int64
    ) -> [PillCountTransactionEntity] {
        
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        
        // Filter: User match + Not Deleted + Created between Start and End time
        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND created_at >= %lld AND created_at <= %lld",
            user, startTime, endTime
        )
        
        // Sort: Newest first
        request.sortDescriptors = [
            NSSortDescriptor(key: "created_at", ascending: false)
        ]
        
        do {
            return try mainThreadContext.fetch(request)
        } catch {
            print("❌ Error fetching filtered transactions: \(error)")
            return []
        }
    }
    
    // MARK: - BULK DELETE TRANSACTION DETAILS
    func softDeleteAllTransactionDetails(for txnId: Int64) {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> =
        PillCountTransactionDetailsEntity.fetchRequest()
        
        request.predicate = NSPredicate(
            format: "txn_id == %lld AND is_deleted == false", txnId
        )
        do {
            let details = try mainThreadContext.fetch(request)
            guard !details.isEmpty else { return }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            
            for detail in details {
                detail.is_deleted = true
                detail.updated_at = now
            }
            
            CoreDataManager.shared.save(context: mainThreadContext)
        } catch {
            print("❌ Failed to delete transaction details for txnId \(txnId): \(error)")
        }
    }
    
    // Delete transaction by step
    func softDeleteTransactionDetailsForStep(
        txnId: Int64,
        step: ControlledStep
    ) {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> =
            PillCountTransactionDetailsEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "txn_id == %lld AND type == %@ AND is_deleted == false",
            txnId,
            step.rawValue
        )

        do {
            let details = try mainThreadContext.fetch(request)

            guard !details.isEmpty else { return }

            let now = Int64(Date().timeIntervalSince1970 * 1000)

            for detail in details {
                detail.is_deleted = true
                detail.updated_at = now
            }

            CoreDataManager.shared.save(context: mainThreadContext)

        } catch {
            print("❌ Failed to delete step details for txnId \(txnId), step \(step): \(error)")
        }
    }
    
    // MARK: UPDATE
    // Update an existing transaction instead of creating a new one
    func updateTransaction(
        txnId: Int64,
        substituedDrugId: Int64? = nil,
        drugId: Int64?,
        countType: CountType,
        targetCount: Int32?,
        barcodeImagePath: String? = nil
    ) {
        guard
            let entity = fetchPillCountTransactionByTransactionId(txnId: txnId)
        else {
            print("❌ No transaction found to update for txnId \(txnId)")
            return
        }

        // Update drug if needed
        if let drugId = drugId,
           let drugEntity = fetchDrugById(drugId) {
            entity.drug_id = drugId
            entity.drug = drugEntity
        }

        // Update core fields
        entity.count_type = countType.rawValue
        entity.is_synced = false
        
        // Update target count ONLY if provided
        if let targetCount {
            entity.target_count = targetCount
        }

        // Update barcode image ONLY if provided
        if let barcodeImagePath, !barcodeImagePath.isEmpty {
            entity.barcode_image = barcodeImagePath
        }

        // Update timestamp
        entity.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)
        debugPrintAllTransactions()
    }
    
    func updateTransactionSynced(txnId: Int64) {

        print("[DB][SYNC] updateTransactionSynced called for txnId =", txnId)

        guard let txn = fetchPillCountTransactionByTransactionId(txnId: txnId) else {
            print("[DB][SYNC] ❌ Transaction NOT FOUND for txnId =", txnId)
            return
        }

        print("[DB][SYNC] Before update → isSynced =", txn.is_synced,
              "status =", txn.status ?? "nil")

        txn.is_synced = true
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)

        print("[DB][SYNC] After update → isSynced =", txn.is_synced)
    }
    
    func updateBatchStatus(batchId: Int64, status: String) {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()

        request.predicate = NSPredicate(format: "batch_id == %lld", batchId)

        if let batch = try? mainThreadContext.fetch(request).first {
            batch.status = status
            CoreDataManager.shared.save(context: mainThreadContext)

            print("Batch status updated to \(status)")
        } else {
            print("Batch not found")
        }
    }
    
    // Update Txn count for stock counts
    func updateCounts(
        txnId: Int64?,
        bottleQty: Int32? = nil,
        looseQty: Int32? = nil
    ) {
        guard let txnId = txnId else {
            print("txnId is nil")
            return
        }
        
        guard let txn = fetchPillCountTransactionByTransactionId(txnId: txnId) else {
            print("No transaction found for txnId \(txnId)")
            return
        }

        //  Add to existing values instead of replacing
        if let bottleQty {
            txn.bottle_qty += bottleQty
        }

        if let looseQty {
            txn.loose_qty += looseQty
        }

        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)

        print("Counts updated → bottle: \(txn.bottle_qty), loose: \(txn.loose_qty)")
    }
    
    
    func clearAllLocalData() {
        
        let context = mainThreadContext
        let fileManager = FileManager.default
        
        do {
            print("Clearing ALL local data...")
            
            // MARK: 1️⃣ Delete All Transaction Details
            let detailFetch: NSFetchRequest<NSFetchRequestResult> = PillCountTransactionDetailsEntity.fetchRequest()
            try context.execute(NSBatchDeleteRequest(fetchRequest: detailFetch))
            
            // MARK: 2️⃣ Delete All Transactions
            let txnFetch: NSFetchRequest<NSFetchRequestResult> = PillCountTransactionEntity.fetchRequest()
            try context.execute(NSBatchDeleteRequest(fetchRequest: txnFetch))
            
            // MARK: 3️⃣ Delete All Batches  ✅ FIX HERE
            let batchFetch: NSFetchRequest<NSFetchRequestResult> = BatchCountEntity.fetchRequest()
            try context.execute(NSBatchDeleteRequest(fetchRequest: batchFetch))
            
            // MARK: 4️⃣ Delete All Drugs
            let drugFetch: NSFetchRequest<NSFetchRequestResult> = DrugMasterEntity.fetchRequest()
            try context.execute(NSBatchDeleteRequest(fetchRequest: drugFetch))
            
            // MARK: 5️⃣ Delete All Images
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let files = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
                for fileURL in files {
                    try? fileManager.removeItem(at: fileURL)
                }
                print("All local image files removed.")
            }
            
            // MARK: 6️⃣ Reset Counters
            UserDefaults.standard.removeObject(forKey: "txnTransactionIdCounter")
            UserDefaults.standard.removeObject(forKey: "txnDetailIdCounter")
            
            try context.save()
            
            print("All local data cleared successfully.")
            
        } catch {
            print("Failed to clear local data:", error)
        }
    }

    
    // For Controlled Drug
    func getTransactionDetailsForStep(
        txnId: Int64,
        step: ControlledStep
    ) -> [PillCountTransactionDetailsEntity] {
        
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> =
            PillCountTransactionDetailsEntity.fetchRequest()
        
        request.predicate = NSPredicate(
            format: "txn_id == %lld AND type == %@ AND is_deleted == false",
            txnId,
            step.rawValue
        )
        
        request.sortDescriptors = [
            NSSortDescriptor(key: "created_at", ascending: true)
        ]
        
        return (try? mainThreadContext.fetch(request)) ?? []
    }
    
    func getTotalCountForStep(
        txnId: Int64,
        step: ControlledStep
    ) -> Int32 {
        
        let details = getTransactionDetailsForStep(
            txnId: txnId,
            step: step
        )
        
        return details.reduce(Int32(0)) { total, item in
            total + item.pill_count
        }
    }
    
    func getLastCompletedStep(txnId: Int64) -> ControlledStep? {

        let request: NSFetchRequest<PillCountTransactionDetailsEntity> =
            PillCountTransactionDetailsEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "txn_id == %lld AND is_deleted == false",
            txnId
        )

        request.sortDescriptors = [
            NSSortDescriptor(key: "created_at", ascending: false)
        ]

        request.fetchLimit = 1

        guard
            let detail = try? mainThreadContext.fetch(request).first,
            let type = detail.type,
            let step = ControlledStep(rawValue: type)
        else {
            return nil
        }

        return step
    }
    
    func getContainerPendingTarget(txnId: Int64) -> Int32 {

        guard let txn = fetchPillCountTransactionByTransactionId(txnId: txnId) else {
            return 0
        }

        let containerCount = getTotalCountForStep(
            txnId: txnId,
            step: .containerInitiate
        )

        let target = txn.target_count

        return max(containerCount - target, 0)
    }
    
    func updateNdcVerified(txnId: Int64, verified: Bool) {

        guard let txn = fetchPillCountTransactionByTransactionId(txnId: txnId) else {
            print("No transaction found for txnId \(txnId)")
            return
        }

        txn.is_ndc_verfied = verified
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)

        print("NDC verification updated for txnId \(txnId) → \(verified)")
    }
    
    // Update drugMaster data
    func updateDrugMaster(
        drugId: Int64,
        drugName: String? = nil,
        ndc: String? = nil,
        gtin: String? = nil,
        drugType: String? = nil,
        packageQty: Int32? = nil
    ) {

        guard let drug = fetchDrugById(drugId) else {
            print("❌ Drug not found for id \(drugId)")
            return
        }

        if let drugName { drug.drug_name = drugName }
        if let ndc { drug.ndc = ndc }
        if let gtin, !gtin.isEmpty { drug.gtin = gtin }
        if let drugType { drug.drug_type = drugType }
        if let packageQty, packageQty > 0 { drug.package_qty = packageQty }

        CoreDataManager.shared.save(context: mainThreadContext)

        print("Drug updated for id \(drugId)")
    }
    
    
    func updateTransactionDrugId(
        txnId: Int64,
        drugId: Int64
    ) {

        guard let txn = fetchPillCountTransactionByTransactionId(txnId: txnId),
              let drug = fetchDrugById(drugId) else {
            print("Failed to update txn drug")
            return
        }

        txn.drug_id = drugId
        txn.drug = drug
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)

        CoreDataManager.shared.save(context: mainThreadContext)

        print("Transaction \(txnId) updated with new drug \(drugId)")
    }
    
    //For Vial txn detail 
    func addOrReplaceVialTransactionDetail(
        txnId: Int64,
        imagePath: String?
    ) {

        let context = mainThreadContext

        context.performAndWait {
            // Delete existing vial
            softDeleteTransactionDetailsForStep(
                txnId: txnId,
                step: .vial
            )

            //  FORCE REFRESH CONTEXT (CRITICAL FIX)
            context.refreshAllObjects()

            //  Add new vial
            addTransactionDetail(
                txnId: txnId,
                pillCount: 0,
                imagePath: imagePath,
                type: ControlledStep.vial.rawValue
            )
        }
    }
    
    func debugPrintFullDatabase() {

        print("\n================= 🧠 FULL DB DUMP =================")

        // MARK: 🟦 BATCHES
        let batchRequest: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        let batches = (try? mainThreadContext.fetch(batchRequest)) ?? []

        print("\n📦 BATCHES: \(batches.count)")
        for batch in batches {
            print("""
            ---------------- BATCH ----------------
            🆔 Batch ID: \(batch.batch_id)
            📅 Start: \(batch.start_date_time)
            📦 Bucket: \(batch.bucket_id ?? "")
            📊 Status: \(batch.status ?? "")
            🗑️ Deleted: \(batch.is_deleted)
            📡 From PMS: \(batch.req_id_from_pms)
               requstId:\(batch.req_id_from_pms)
            ---------------------------------------
            """)
        }

        // MARK: 🟩 DRUG MASTER
        let drugRequest: NSFetchRequest<DrugMasterEntity> = DrugMasterEntity.fetchRequest()
        let drugs = (try? mainThreadContext.fetch(drugRequest)) ?? []

        print("\n💊 DRUG MASTER: \(drugs.count)")
        for drug in drugs {
            print("""
            ---------------- DRUG ----------------
            🆔 Drug ID: \(drug.drug_id)
            💊 Name: \(drug.drug_name ?? "")
            🔢 NDC: \(drug.ndc ?? "")
            📦 GTIN: \(drug.gtin ?? "")
            📊 Package Qty: \(drug.package_qty)
            -------------------------------------
            """)
        }

        // MARK: 🟥 TRANSACTIONS
        let txnRequest: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        let txns = (try? mainThreadContext.fetch(txnRequest)) ?? []

        print("\n🧾 TRANSACTIONS: \(txns.count)")
        for txn in txns {
            print("""
            ---------------- TXN ----------------
            🆔 Txn ID: \(txn.txn_id)
            📦 Batch ID: \(txn.batch_id)
            💊 Drug: \(txn.drug?.drug_name ?? "")
            🔢 NDC: \(txn.drug?.ndc ?? "")
            📦 Bucket: \(txn.bucket_id ?? "")
            📅 Created: \(txn.created_at)

            🧴 Bottle Qty: \(txn.bottle_qty)
            💊 Loose Qty: \(txn.loose_qty)
            🎯 Target: \(txn.target_count)

            📆 Expiry: \(txn.expiry ?? "")
            🏷 Lot: \(txn.lot_no ?? "")

            📡 From PMS: \(txn.is_from_pms)
            🔄 Synced: \(txn.is_synced)
            🗑️ Deleted: \(txn.is_deleted)
            ------------------------------------
            """)
        }

        // MARK: 🟨 TRANSACTION DETAILS
        let detailRequest: NSFetchRequest<PillCountTransactionDetailsEntity> =
            PillCountTransactionDetailsEntity.fetchRequest()
        let details = (try? mainThreadContext.fetch(detailRequest)) ?? []

        print("\n📑 TXN DETAILS: \(details.count)")
        for d in details {
            print("""
            ------------- DETAIL -------------
            🆔 Detail ID: \(d.txn_details_id)
            🔗 Txn ID: \(d.txn_id)
            💊 Count: \(d.pill_count)
            🖼 Image: \(d.image_path ?? "")
            🧭 Type: \(d.type ?? "")
            🗑️ Deleted: \(d.is_deleted)
            ----------------------------------
            """)
        }

        print("\n================= END DB DUMP =================\n")
    }

    // MARK: DEBUGGING
    func debugPrintAllTransactions() {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        
        do {
            let allTxns = try mainThreadContext.fetch(request)
            print("\n🔍 [DB DUMP] Total Transactions: \(allTxns.count)")
            for txn in allTxns {
                print("""
                    ---------------------------------------------------
                    🆔 Txn ID: \(txn.txn_id)
                    💊 Drug: \(txn.drug?.drug_name ?? "nil")
                    👤 User ID: \(txn.user?.user_id ?? "nil")
                    📅 Created: \(txn.created_at)
                    📊 Status: \(txn.status ?? "nil")
                    🔢 Type: \(txn.count_type ?? "nil")
                    🗑️ Deleted: \(txn.is_deleted)
                       isComingFromPms \(txn.is_from_pms)
                       isSynced \(txn.is_synced)
                       package quantity \(txn.drug?.package_qty ?? 0)
                       expirary \(txn.expiry)
                       lotno \(txn.lot_no)
                    ---------------------------------
                    ------------------
                    """)
            }
        } catch {
            print("❌ Failed to fetch debug transactions: \(error)")
        }
    }
}
