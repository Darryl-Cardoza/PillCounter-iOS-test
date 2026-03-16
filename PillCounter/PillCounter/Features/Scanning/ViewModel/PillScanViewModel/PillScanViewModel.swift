//
//  PillScanViewModel.swift
//  PillCounter
//
//  Created by HC on 17/11/25.
//

import Foundation
import SwiftUI
import ComposeApp
import Combine

@MainActor
class PillScanViewModel: ObservableObject {

    // local storage // db
    let pillDataLocalStorage = PillsDataLocalStorage.shared

    // user storage // db
    let userDataLocalStorage = UserLocalDataSource.shared

    // decode the values of the barcode or qr, calling the api, processing it, storing it in database
    // decoder
    let decoder = BarcodeAndQRDecoder()
    let userRepo = UserRepository.shared

    // published properties.
    @Published var drugName: String?

    @Published var drugNameMannuallyEntered: String = ""
    @Published var isDrugFound: Bool?

    @Published var mannualDrugCreated: Bool?

    // now when user mannually enters the ndc number.
    @Published var ndcNumber: String = ""

    // set the target count for fixed or dispense count
    @Published var targetCount: [String] = Array(repeating: "", count: 4)

    // this will hold the current scanning transaction that user is performing or working with.
    @Published var currentTransaction: PillCountTransactionEntity?

    // this will store the transaction details array for the current transaction.
    @Published var currentTransactionTransactionDetails:
        [PillCountTransactionDetailsEntity]?

    // published variable to store the note.
    @Published var note: String = ""
    
    @Published var selectedTransaction: PillCountTransactionEntity?

    // get the user id
    @AppStorage(AppStorageManager.AppStorageKeys.userId) var userId: String = ""
    let doubleCountRequired = AppStorageManager.shared.isDoubleCountRequired
    let backCountRequired = AppStorageManager.shared.isBackCountRequired
        

    private var cancellables = Set<AnyCancellable>()
    
    
    //Controlled Drug Repository
    let controlledRepo  = ControlledRepository.shared

    //Toast
    @Published  var showToast: Bool = false
    @Published  var toastMessage: String = ""

    // To Manager Controlled Drug Step
    @Published var currentControlledStep: ControlledStep = .scan
    @Published var currentControlledTargetCount: Int? = nil
    @Published var showCompletionPopup = false

    // Controlled drug Equivalence
    @Published var isCheckingNdc: Bool = false
    @Published var ndcComparisonResponse: NdcComparisonResponse?
    @Published var isNdcEquivalent: Bool = false
    @Published var showNdcEquivalencePopup = false
    
    
    // func to get the value from the barcode and check in the db
    // if there in the db get the drug from there other wise call the api.
    // func to get the value from the barcode and check in the db
    // if there in the db get the drug from there other wise call the api.
    func scannedPill(
        rawValueFromBarcodeOrQr: String,
        countType: CountType,
        image: UIImage? = nil
    ) async {
        
        let decodedGs1Value = decoder.decode(rawValueFromBarcodeOrQr)
        let gtin = decodedGs1Value.gtin ?? ""

        if gtin.isEmpty { return }
        
       
        // 1. Generate a potential ID (only used if we create a NEW drug)
        var drugIdToUse = generateUniqueDrugId()

        // 2. CHECK LOCAL DB
        if let drugFoundInLocalStorage = pillDataLocalStorage.getPillByNdc(
            by: gtin)
        {

            drugName = drugFoundInLocalStorage.drug_name

            // FIX: Use the EXISTING ID from the database
            drugIdToUse = drugFoundInLocalStorage.drug_id

            await createTransaction(
                drugId: drugIdToUse,
                countType: countType,
                barcodeImage: image
            )
            getAllTransactionDetailsOfTheCurrentTransaction()
            isDrugFound = true
            if countType == .FIXED {
                updateTargetCountForCurrentTransaction()
            }
            return
        }

        // 3. API CALL (If not found locally)
        do {
            let getDrugNameResult = try await userRepo.getDrug(ndc: gtin)

            if getDrugNameResult.isSuccess ?? false {
                drugName = getDrugNameResult.data?.genericName ?? "Loading..."

                if getDrugNameResult.data != nil {
                    // Save new pill (using the NEW unique ID)
                    self.pillDataLocalStorage.savePill(
                        from: getDrugNameResult,
                        ndc: gtin,
                        drugId: drugIdToUse
                    )
                }

                // Create transaction using the NEW ID (since we just saved it)
                await createTransaction(
                    drugId: drugIdToUse,
                    countType: countType,
                    barcodeImage: image
                )

                if countType == .FIXED {
                    updateTargetCountForCurrentTransaction()
                }
                getAllTransactionDetailsOfTheCurrentTransaction()
                isDrugFound = true

            } else {
                isDrugFound = false
            }

        } catch {
            DispatchQueue.main.async { self.isDrugFound = false }
        }
    }
    
    
    func scnnedPmsPill(
        rawValueFromBarcodeOrQr: String,
        countType: CountType,
        image: UIImage? = nil
    ) {


        let decodedGs1Value = decoder.decode(rawValueFromBarcodeOrQr)
        let gtin = decodedGs1Value.gtin ?? ""


        if gtin.isEmpty {
            return
        }


        // Generate potential ID
        var drugIdToUse = generateUniqueDrugId()

        if let drugFoundInLocalStorage = pillDataLocalStorage.getPillByNdc(by: gtin) {


            drugName = drugFoundInLocalStorage.drug_name

            // Use existing ID
            drugIdToUse = drugFoundInLocalStorage.drug_id

            Task(priority: .background) {
                await updaetTransaction(
                    drugId: drugIdToUse,
                    countType: countType,
                    txnId: selectedTransaction?.txn_id ?? 0,
                    barcodeImage: image
                )
            }

            getAllTransactionDetailsOfTheCurrentTransaction()

            isDrugFound = true

            if countType == .FIXED {
                updateTargetCountForCurrentTransaction()
            }

            return
        }

        isDrugFound = true
    }
    

    func getFixedCount() -> Int32? {
        guard let txn = selectedTransaction else {
            return nil
        }

        guard txn.is_from_pms else {
            return nil
        }
        return txn.target_count
    }



    private func generateUniqueDrugId() -> Int64 {
        let defaults = UserDefaults.standard

        let current = defaults.integer(
            forKey: AppStorageManager.AppStorageKeys.drugIdCounter)
        let newId = current + 1

        defaults.set(
            newId, forKey: AppStorageManager.AppStorageKeys.drugIdCounter)

        return Int64(newId)
    }
    
    func log(_ message: String) {
        print("🧪 [ManualPillFlow] \(message)")
    }
    
    func manuallyEnteredPill(
           ndc: String, countType: CountType, isFixedCount: Bool = false
       ) async {

           // check in the database first
           if let drugFoundInLocalStorage = pillDataLocalStorage.getPillByNdc(
               by: ndc)
           {
               isDrugFound = true
               drugName = drugFoundInLocalStorage.drug_name
               // after the drug is found from the db we create a new transaction.
               await createTransaction(
                   drugId: drugFoundInLocalStorage.drug_id, countType: countType)
               getAllTransactionDetailsOfTheCurrentTransaction()
               if countType == .FIXED {
                   updateTargetCountForCurrentTransaction()
               }
               return
           }

           // if not found in the db then call the api

           do {
               let getDrugResult = try await userRepo.getDrug(ndc: ndc)

               if getDrugResult.isSuccess ?? false {
                   isDrugFound = true
                   drugName = getDrugResult.data?.genericName ?? "Loading..."

                   // generating new drug id for each pill
                   let drugId = generateUniqueDrugId()

                   // on success if the result has data in it then only store that data in the db. other wise return and ask the user to enter the ndc number manually.

                   if getDrugResult.data != nil {
                       // background task to save pill in background.
                       Task(priority: .background) {
                           self.pillDataLocalStorage.savePill(
                               from: getDrugResult,
                               ndc: ndc,
                               drugId: drugId
                           )
                       }
                   }
                   // create transaction for the pill if we get the details of the pill from api.
                   // drug id is being generated in the view model since saving of the pill in db should be in the background and the logic generation should be in the view model.
                   // also for creating the transaction we would be needing the drug id.
                   await createTransaction(drugId: drugId, countType: countType)
                   if isFixedCount {
                       updateTargetCountForCurrentTransaction()
                   }
                   getAllTransactionDetailsOfTheCurrentTransaction()

               } else {
                   isDrugFound = false
                   mannualDrugCreated = true
                   
                   drugName = drugNameMannuallyEntered

                   let drugId = generateUniqueDrugId()

                   Task(priority: .background) {
                       self.pillDataLocalStorage.saveManualPill(
                           ndc: ndc,
                           drugId: drugId,
                           drugName: drugNameMannuallyEntered
                       )
                   }

                   await createTransaction(drugId: drugId, countType: countType)
                   
                   if countType == .FIXED {
                       self.updateTargetCountForCurrentTransaction()
                   }

                   getAllTransactionDetailsOfTheCurrentTransaction()
               }

           } catch let error {
               DispatchQueue.main.async {
                   self.isDrugFound = nil
                   print("Error: \(error)")

                   self.mannualDrugCreated = true

                   let drugId = self.generateUniqueDrugId()

                   Task(priority: .background) {
                       self.pillDataLocalStorage.saveManualPill(
                           ndc: ndc,
                           drugId: drugId,
                           drugName: self.drugNameMannuallyEntered
                       )
                   }
                   
                   self.drugName = self.drugNameMannuallyEntered

                   Task {
                       await self.createTransaction(
                           drugId: drugId,
                           countType: countType
                       )
                       if countType == .FIXED {
                           self.updateTargetCountForCurrentTransaction()
                       }
                   }

                   self.getAllTransactionDetailsOfTheCurrentTransaction()

               }
           }
       }

    func manualEntryDirectUpsert(
        ndc: String,
        drugName: String,
        countType: CountType
    ) async {

        let trimmedNdc = ndc.trimmingCharacters(in: .whitespaces)
        let trimmedDrugName = drugName.trimmingCharacters(in: .whitespaces)

        guard !trimmedNdc.isEmpty else {
            return
        }

        var drugIdToUse: Int64

        // Check if drug already exists in DB
        if let existingDrug = pillDataLocalStorage.getPillByNdc(by: trimmedNdc) {

            // Use existing drug
            drugIdToUse = existingDrug.drug_id
            self.drugName = existingDrug.drug_name

        } else {

            //  Create new drug entry
            drugIdToUse = generateUniqueDrugId()

            pillDataLocalStorage.saveManualPill(
                ndc: trimmedNdc,
                drugId: drugIdToUse,
                drugName: trimmedDrugName
            )

            self.drugName = trimmedDrugName
        }

        // Create transaction (ONLY for selected drug)
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType
        )

        //  Update target if FIXED
        if countType == .FIXED {
            updateTargetCountForCurrentTransaction()
        }

        //  Refresh details
        getAllTransactionDetailsOfTheCurrentTransaction()

        // Trigger navigation state
        self.isDrugFound = true
        self.mannualDrugCreated = true
    }
    
    // create transaction for every new transaction that user scans the barcode or enters the ndc or the gtin number manually.
    func createTransaction(
        drugId: Int64, countType: CountType,
        barcodeImage: UIImage? = nil,
        isComingFromPms:Bool = false,
        isControlled:Bool? = nil,
        targetCount: Int32? = nil,
        drugName: String? = nil
    ) async {
        // creating the transaction for the pill.
        // step1: get the user.
        guard
            !userId.isEmpty,
            let user = userDataLocalStorage.getUserByUserId(by: userId)
        else {
            return
        }

        // Save Image using Helper if it exists
        var savedPath = ""

        if let img = barcodeImage {
            print("📸 Barcode image exists")

            if let path = PhotoFileManager.shared.saveImage(img) {
                savedPath = path
            } else {
                print("❌ Failed to save image")
            }

        } else {
            print("⚠️ barcodeImage is nil")
        }

        print("🗂 Final Image Path Being Sent To DB: \(savedPath)")


        // step 2: we have got all, user id, drugId, count type, for now the barcode image is set to empty string.
        // we now call the db function to create the transaction.
        pillDataLocalStorage.createTransaction(
            for: user,
            drugId: drugId,
            countType: countType,
            barcodeImagePath: savedPath,
            isComingFromPms: isComingFromPms,
            drugName: drugName,
            targetCount: targetCount,
            isControlled: isControlled // temporary true
        )
    

        // step 3: set the latest transaction as current transaction.
        if let latest = pillDataLocalStorage.fetechLatestTransactionOfUser(
            for: user)
        {
            self.currentTransaction = latest
        }
    }
    
    func updaetTransaction(
        drugId: Int64,
        countType: CountType,
        txnId:Int64,
        barcodeImage: UIImage? = nil,
        isComingFromPms:Bool = false,
        targetCount: Int32? = nil
    ) async {
        
        // creating the transaction for the pill.
        // step1: get the user.
        guard
            !userId.isEmpty,
            let user = userDataLocalStorage.getUserByUserId(by: userId)
        else {
            return
        }

        // Save Image using Helper if it exists
        var savedPath = ""
        if let img = barcodeImage {

            print("📸 Image size:", img.size)

            if let path = PhotoFileManager.shared.saveImage(img) {
                savedPath = path
                print("✅ Image saved at:", path)
            } else {
                print("❌ Failed to save image")
            }

        } else {
            print("⚠️ barcodeImage is nil")
        }


        // step 2: we have got all, user id, drugId, count type, for now the barcode image is set to empty string.
        // we now call the db function to create the transaction.
        pillDataLocalStorage.updateTransaction(
            txnId: txnId,
            drugId: drugId,
            countType: countType,
            targetCount: targetCount,
            barcodeImagePath: savedPath
        )

        // step 3: set the latest transaction as current transaction.
        if let latest = pillDataLocalStorage.fetechLatestTransactionOfUser(
            for: user)
        {
            self.currentTransaction = latest
        }

    }

    // create a func to get all the transactions of the current transaction.
//    func getAllTransactionDetailsOfTheCurrentTransaction() {
//        currentTransactionTransactionDetails =
//            pillDataLocalStorage.getTransactionDetailsByTransactionId(
//                txnId: currentTransaction?.txn_id ?? 0)
//    }
//
    
    func getAllTransactionDetailsOfTheCurrentTransaction() {
        guard let txnId = currentTransaction?.txn_id else { return }
        currentTransactionTransactionDetails =
            PillsDataLocalStorage.shared
                .getTransactionDetailsForStep(
                    txnId: txnId,
                    step: currentControlledStep
                )
    }

    // function to add transaction detail to the current transaction.
    // this will be the function which will get the pill count from the model, the image path that we will capture and store it in the db.
    func addTransactionDetailToCurrentTransaction(
        pillCount: Int32,
        imagePath: String? = nil,
        type: String? = nil,
        isManual: Bool = false
    ) {

        // first check if the current transaction id is there or not.
        guard let txnId = currentTransaction?.txn_id else {
            return
        }

        pillDataLocalStorage.addTransactionDetail(
            txnId: txnId,
            pillCount: pillCount,
            imagePath: imagePath,
            type: type,
            isManual: isManual
        )

        getAllTransactionDetailsOfTheCurrentTransaction()
    }

    // if the user selects the fixed or dispense count then he has to set the target.
    // this function will set the target count for the current transaction.
    // if the user selects the fixed or dispense count then he has to set the target.
    // this function will set the target count for the current transaction.
    func updateTargetCountForCurrentTransaction() {

        let joinedString = targetCount.joined()

        // 1. Check if the string is empty first
        if joinedString.isEmpty {
            return
        }

        // 2. Convert to Int32 safely
        guard let targetValue = Int32(joinedString) else {
            return
        }

        guard let txnId = currentTransaction?.txn_id else {
            return
        }

        pillDataLocalStorage.updateTargetCount(
            txnId: txnId, targetCount: targetValue)

        // update the current transaction for updating the ui.
        if let updatedTxn =
            pillDataLocalStorage.fetchPillCountTransactionByTransactionId(
                txnId: txnId)
        {
            self.currentTransaction = updatedTxn
        }
    }

    // helper function to return the total number of pills.
    // function to get the total count of all the transaction details of that transaction.
    // Helper function to return the total number of pills.
    // If 'details' is passed, it calculates the total for that array.
    // Otherwise, it uses the currently selected transaction details.
    func getTotalPillCountOfCurrentTransaction(
        details: [PillCountTransactionDetailsEntity]? = nil
    ) -> Int {
        // Priority:
        // 1. Parameter passed in function call
        // 2. The @Published property 'currentTransactionTransactionDetails'
        // 3. Empty array (safeguard)
        let sourceDetails =
            details ?? currentTransactionTransactionDetails ?? []

        let total = sourceDetails.reduce(0) { $0 + Int($1.pill_count) }
        return total
    }
    
    
    func getTotalPillCountOfCurrentTransactionByType(
        type: ControlledStep,
        details: [PillCountTransactionDetailsEntity]? = nil
    ) -> Int {

        // Priority:
        // 1. Parameter passed in function call
        // 2. The @Published property 'currentTransactionTransactionDetails'
        // 3. Empty array (safeguard)
        let sourceDetails = details ?? currentTransactionTransactionDetails ?? []

        let total = sourceDetails
            .filter { $0.type == type.rawValue }
            .reduce(0) { $0 + Int($1.pill_count) }

        return total
    }

    func updateNoteForCurrentTransaction(txn_id: Int64, note: String) {
        pillDataLocalStorage.updateNote(txnId: txn_id, note: note)
    }

    // func to get the current transaction
//    func getCurrentTransaction(txnId: Int64) async {
//        // Fetch transaction
//        currentTransaction =
//            pillDataLocalStorage.fetchPillCountTransactionByTransactionId(
//                txnId: txnId)
//
//        // Set drug name
//        drugName = currentTransaction?.drug?.drug_name ?? "Unknown"
//
//        // Fetch details
//        getAllTransactionDetailsOfTheCurrentTransaction()
//
//        let count = currentTransactionTransactionDetails?.count ?? 0
//
//        if count > 0 {
//            let totalPills = getTotalPillCountOfCurrentTransaction()
//        }
//    }

    func getCurrentTransaction(txnId: Int64) async {

        // Fetch transaction
        currentTransaction =
            pillDataLocalStorage.fetchPillCountTransactionByTransactionId(
                txnId: txnId
            )

        // Set drug name
        drugName = currentTransaction?.drug?.drug_name ?? "Unknown"

        // Fetch details
        getAllTransactionDetailsOfTheCurrentTransaction()

        let count = currentTransactionTransactionDetails?.count ?? 0

        if count > 0 {
            let totalPills = getTotalPillCountOfCurrentTransaction()
            print("Total pills counted: \(totalPills)")
        }
    }
    
    // soft delete the pill transaction detail of the current transaction.
    func softDeleteCurrentTransactionSelectedTransactionDetail(
        txnDetailId: Int64
    ) {
        pillDataLocalStorage.updatePillCountTransactionDetailById(
            txnDetailId: txnDetailId
        ) { transactionDetails in
            transactionDetails.is_deleted = true
        }

        getAllTransactionDetailsOfTheCurrentTransaction()
    }
    
    
    func deleteAllDetailsOfCurrentTransaction() {
        guard let txnId = currentTransaction?.txn_id else {
            return
        }

        pillDataLocalStorage.softDeleteTransactionDetailsForStep(txnId: txnId, step: currentControlledStep)

        // Refresh in-memory state to update UI
        getAllTransactionDetailsOfTheCurrentTransaction()
    }

    func resetScanningState() {
        self.isDrugFound = nil
        self.drugName = nil
        self.currentTransaction = nil
        self.currentTransactionTransactionDetails = nil
        self.ndcNumber = ""
        self.targetCount = ["", "", "", ""]
    }
    
    @MainActor
    func autofillDrugNameIfAvailable(for ndc: String) {
        guard ndc.count >= 20 else { return }

        let storage = PillsDataLocalStorage.shared

        if let drug = storage.getPillByNdc(by: ndc),
           let drugName = drug.drug_name,
           !drugName.isEmpty {

            // Auto-fill ONLY if user has not typed anything
            if drugNameMannuallyEntered.isEmpty {
                drugNameMannuallyEntered = drugName
            }
        }
    }

    
    // Message handling for transaction coming from pms
    typealias HL7SimpleCallback = (Bool) -> Void
    
    //ShowToastMessage
    func showToastMessage(text: String) {
        toastMessage = text
        showToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showToast = false
        }
    }

    
    func handleReceivedMessage(
        message: CompleteHL7Message,
        callback: HL7SimpleCallback? = nil
    ){
        print("Received message parsed message \(message)")
        guard let inboundType = classifyInboundMessage(message) else {
            return
        }
        
        print("Message Type \(inboundType)")

        Task(priority: .background) {
            switch inboundType {
            case .FIXED:
                 await createFixedHl7Transaction(message:message, inboundType: .FIXED, callback: callback)

            case .REGULAR:
                 await createRegularHl7Transaction(message:message, inboundType: .REGULAR, callback: callback)
            }
        }
    }
    
    
    @MainActor
    private func createFixedHl7Transaction(
        message: CompleteHL7Message,
        inboundType: CountType,
        callback: HL7SimpleCallback? = nil
    ) async {

        guard let order = message.order else {
            print("HL7 Error: Missing ORC segment")
            callback?(false)
            return
        }

        let orderId = order.placerOrderId
        print("PMS Order ID: \(orderId)")

        guard !message.medications.isEmpty else {
            print("HL7 Error: No RXE medication segments")
            callback?(false)
            return
        }

        for medication in message.medications {

            // RXE-2.1
            let ndc = medication.drugCode.trimmingCharacters(in: .whitespacesAndNewlines)

            // RXE-2.2
            let drugName = medication.drugName

            // RXE-3
            let targetCount = Int32(medication.requestedQty ?? "0") ?? 0

            print("""
            PMS HL7 Request
            Order: \(orderId)
            Drug: \(drugName)
            NDC: \(ndc)
            Target Count: \(targetCount)
            """)

            await processHl7DrugAndCreateTransaction(
                ndc: ndc,
                drugName: drugName,
                countType: inboundType,
                targetCount: targetCount
            )
        }

        callback?(true)
    }
    
    @MainActor
    private func createRegularHl7Transaction(
        message: CompleteHL7Message,
        inboundType: CountType,
        callback: HL7SimpleCallback? = nil
    ) async {
    
        guard let inventory = message.inventoryItems.first else {
            print("Regular Count: No RXE medication found")
            return
        }

        let ndc = inventory.substanceCode ?? ""
        let drugName = inventory.description
          
        print("Regular Count Drug Info: \(ndc), \(drugName)")

        await processHl7DrugAndCreateTransaction(
            ndc: ndc,
            drugName: drugName,
            countType: inboundType
        )
        callback?(true)
    }


    
    private func classifyInboundMessage(
        _ message: CompleteHL7Message
    ) -> CountType? {

        if message.messageType == "RDE",
           message.triggerEvent == "O11",
           !message.medications.isEmpty {
            return .FIXED
        }

        if message.messageType == "INR",
           message.triggerEvent == "U06",
           !message.inventoryItems.isEmpty {
            return .REGULAR
        }

        return nil
    }

    
    @MainActor
    func processHl7DrugAndCreateTransaction(
        ndc: String,
        drugName: String,
        countType: CountType,
        targetCount: Int32? = nil
    ) async {

        print("🧾 HL7 Drug Processing → NDC: \(ndc), Name: \(drugName)")

        var drugIdToUse: Int64

        // 1️⃣ Check if drug exists
        if let existingDrug = pillDataLocalStorage.getPillByNdc(by: ndc) {

            print("Drug found in DrugMaster (id: \(existingDrug.drug_id))")

            drugIdToUse = existingDrug.drug_id
            self.drugName = existingDrug.drug_name

        } else {

            // 2️⃣ Create new drug synchronously
            drugIdToUse = generateUniqueDrugId()

            print("Drug not found — creating new DrugMaster entry")

            pillDataLocalStorage.saveManualPill(
                ndc: ndc,
                drugId: drugIdToUse,
                drugName: drugName
            )

            self.drugName = drugName
        }

        // 3️⃣ Create transaction
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            isComingFromPms: true,
            isControlled: true,
            targetCount: targetCount,
            drugName: drugName
        )

        // 4️⃣ Refresh transaction details
        getAllTransactionDetailsOfTheCurrentTransaction()

        // 5️⃣ Update target count if fixed
        if countType == .FIXED {
            updateTargetCountForCurrentTransaction()
        }
    }
    
    
    // MARK: - HARD LOGOUT RESET
    @MainActor
    func resetState() {

        cancellables.removeAll()

        drugName = nil
        drugNameMannuallyEntered = ""
        isDrugFound = nil
        mannualDrugCreated = nil

        // Counting
        targetCount = ["", "", "", ""]
        note = ""
        // Transactions
        currentTransaction = nil
        currentTransactionTransactionDetails = nil
        selectedTransaction = nil
        
        showNdcEquivalencePopup = false
        isCheckingNdc = false
        isNdcEquivalent = false
        ndcComparisonResponse = nil

    }

}


//Controlled Drug
extension PillScanViewModel{
    
    var activeTransaction: PillCountTransactionEntity? {
        if let currentTransaction {
            return currentTransaction
        }

        if let selectedTransaction {
            return selectedTransaction
        }

        return nil
    }


    
    
    func getCurrentControlledTransaction(txnId: Int64) async {

        // Fetch transaction
        currentTransaction =
        pillDataLocalStorage.fetchPillCountTransactionByTransactionId(
            txnId: txnId
        )

        // Drug name
        drugName = currentTransaction?.drug?.drug_name ?? "Unknown"

        // Load details
        getAllTransactionDetailsOfTheCurrentTransaction()

        // Restore correct step
        getControlledStep()

        // Calculate target for step
        updateControlledTargetCount()
    }
    
    
    // MARK: - Update Target Count
    

    
    func updateControlledTargetCount() {

        guard let txn = currentTransaction else { return }
        log("❌ updateControlledTargetCount: transaction missing")

        let target = Int(txn.target_count)
        log("Updating target for step \(currentControlledStep.rawValue) target \(target)")

        let txnId = txn.txn_id

        switch currentControlledStep {
            
        case .scan:
            currentControlledTargetCount = 0
            
        case .containerInitiate:
            currentControlledTargetCount = 0

        case .targetVerification,
             .targetReverification,
             .vial:
            currentControlledTargetCount = target

        case .containerPending:

            let containerCount =
            pillDataLocalStorage.getTotalCountForStep(
                txnId: txnId,
                step: .containerInitiate
            )

            currentControlledTargetCount =
            max(Int(containerCount) - target, 0)
        }
    }
    
    // Check is this step can be completed or not
    func canCompleteStep(stepTotal: Int) -> Bool {

        guard let txn = currentTransaction else { return false }

        let target = Int(txn.target_count)

        switch currentControlledStep {

        case .containerInitiate:
            return stepTotal > 0
            
        case .targetVerification:
            if currentTransaction?.count_type == CountType.FIXED.rawValue {
                return stepTotal == target
            } else {
                return stepTotal > 0
            }
            
        case .targetReverification:
            return stepTotal == target

        case .containerPending:
            let containerCount =
            pillDataLocalStorage.getTotalCountForStep(
                txnId: txn.txn_id,
                step: .containerInitiate
            )
            let expected = Int(containerCount) - target
            return stepTotal == expected
            
        case .vial:
            return stepTotal == 0

        default:
            return false
        }
    }
    
    
    func getTotalCuntForCurrentStep() -> Int32 {

        guard let txnId = currentTransaction?.txn_id else {
            return 0
        }

        let total = pillDataLocalStorage.getTotalCountForStep(
            txnId: txnId,
            step: currentControlledStep
        )

        return total
    }
    
    
    // Get Last saved Controlled Step
    func getLastSavedControlledStep() -> ControlledStep? {
        guard let txn = selectedTransaction else { return nil }
        return pillDataLocalStorage.getLastCompletedStep(txnId: txn.txn_id)
    }
    
    
    // Get which Controlled step is now
    func getControlledStep(pillCountTxn: PillCountTransactionEntity? = nil) {

        guard let txn = pillCountTxn else {
            return
        }

        let steps = PillCountingStepResolver.getActiveSteps(txn: txn)

        // Fetch last saved step
        guard let lastStep = pillDataLocalStorage.getLastCompletedStep(txnId: txn.txn_id) else {
            if txn.is_from_pms == true {
                currentControlledStep = .containerInitiate
            } else {
                currentControlledStep = .targetVerification
            }

            updateControlledTargetCount()
            return
        }


//        if lastStep == .vial {
//            if steps.contains(.containerPending) {
//                currentControlledStep = .containerPending
//            } else {
//                currentControlledStep = .containerPending
//            }
//
//            updateControlledTargetCount()
//            return
//        }

        currentControlledStep = lastStep
        updateControlledTargetCount()
    }
    
    
    // When step completed
    func handleStepCompletion() {
        guard let txn = currentTransaction else {
            return
        }
        let steps = PillCountingStepResolver.getActiveSteps(txn: txn)

        guard let currentIndex = steps.firstIndex(of: currentControlledStep) else {
            return
        }
        let next = steps[currentIndex + 1]
        currentControlledStep = next
        updateControlledTargetCount()
    }
    
    //Update Drug Data
    func updateSubstitutedDrug(
        txnId: Int64,
        rawValue: String,
        countType: CountType,
        image: UIImage?
    ) async {

        let decoded = decoder.decode(rawValue)
        let gtin = decoded.gtin ?? ""

        guard !gtin.isEmpty else { return }

        // create new drug
        let drugId = generateUniqueDrugId()

        pillDataLocalStorage.saveManualPill(
            ndc: ndcComparisonResponse?.data?.scannedNdc.packageNdc ?? "",
            drugId: drugId,
            drugName: ndcComparisonResponse?.data?.scannedNdc.lookupName ?? "",
            drugType: ndcComparisonResponse?.data?.scannedNdc.deaSchedule ?? "",
        )

        var savedPath = ""

        if let img = image {
            if let path = PhotoFileManager.shared.saveImage(img) {
                savedPath = path
            }
        }

        pillDataLocalStorage.updateTransaction(
            txnId: txnId,
            drugId: drugId,
            countType: countType,
            targetCount: nil,
            barcodeImagePath: savedPath
        )

        isDrugFound = true
    }
}
