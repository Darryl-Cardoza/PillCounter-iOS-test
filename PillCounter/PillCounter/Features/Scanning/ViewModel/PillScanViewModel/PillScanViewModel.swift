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
    @Published var drugName: String? = nil

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

    // MARK: Controlled drug Equivalence
    @Published var isCheckingNdc: Bool = false
    @Published var ndcComparisonResponse: NdcComparisonResponse?
    @Published var isNdcEquivalent: Bool = false
    @Published var showNdcEquivalencePopup = false
    @Published var shouldAutoProceedToCount = false
    @Published var isNdcAdded: Bool = false
    
    // MARK: Stock Count State
    @Published var addCurrentOpenPillCount: Int = 0

    // Set to true before pushing to PillScanDetailGridScreen so onDisappear
    // in PillCountView knows not to clear transaction data mid-push.
    var isNavigatingToDetailGrid: Bool = false

    //MARK: RX FLow
    @Published var showRxFlowPopup: Bool = false
    @Published var scannedRxData: ParsedScanData? = nil
    @Published var bucketOptions: [String] = []
    @Published var selectedBucket: String = ""
    @Published var showScannedDrugInfoPopoup: Bool = false
    
    // func to get the value from the barcode and check in the db
    // if there in the db get the drug from there other wise call the api.
    // func to get the value from the barcode and check in the db
    // if there in the db get the drug from there other wise call the api.
    func scannedPill(
        rawValueFromBarcodeOrQr: String,
        countType: CountType,
        image: UIImage? = nil
    ) async {

        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let gtin = decoded.gtin ?? ""

        await handleDrugFlow(
            ndc: gtin,
            countType: countType,
            image: image
        )
    }
    
    private func handleDrugFlow(
        ndc: String,
        countType: CountType,
        image: UIImage? = nil,
        fallbackDrugName: String? = nil
    ) async {

        guard !ndc.isEmpty else { return }

        var drugIdToUse = generateUniqueDrugId()

        // 1. Check local DB
        if let localDrug = pillDataLocalStorage.getPillByNdc(by: ndc) {

            drugName = localDrug.drug_name ?? ""
            drugIdToUse = localDrug.drug_id

            await createTransaction(
                drugId: drugIdToUse,
                countType: countType,
                barcodeImage: image
            )

            postTransactionUIUpdate(countType: countType)
            return
        }

        // 2. API call
        do {
            let result = try await userRepo.getDrug(ndc: ndc)

            if result.isSuccess ?? false, let data = result.data {

                drugName = data.genericName ?? fallbackDrugName ?? ""

                pillDataLocalStorage.savePill(
                    from: result,
                    ndc: ndc,
                    drugId: drugIdToUse
                )

            } else {
                // fallback for manual entry
                guard let fallbackDrugName else {
                    isDrugFound = false
                    return
                }

                drugName = fallbackDrugName

                pillDataLocalStorage.saveManualPill(
                    ndc: ndc,
                    drugId: drugIdToUse,
                    drugName: fallbackDrugName
                )
            }

            // 3. Create transaction
            await createTransaction(
                drugId: drugIdToUse,
                countType: countType,
                barcodeImage: image
            )

            postTransactionUIUpdate(countType: countType)

        } catch {
            print("❌ API error:", error)
            isDrugFound = false
        }
    }
    
    
    private func postTransactionUIUpdate(countType: CountType) {
        getAllTransactionDetailsOfTheCurrentTransaction()

        if countType == .FIXED {
            updateTargetCountForCurrentTransaction()
        }

        isDrugFound = true
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


            drugName = drugFoundInLocalStorage.drug_name ?? ""

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


    func generateUniqueDrugId() -> Int64 {
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
    
//    func manualEntryDirectUpsert(
//        ndc: String,
//        drugName: String,
//        countType: CountType
//    ) async {
//
//        let trimmedNdc = ndc.trimmingCharacters(in: .whitespaces)
//        let trimmedDrugName = drugName.trimmingCharacters(in: .whitespaces)
//
//        guard !trimmedNdc.isEmpty else { return }
//
//        await handleDrugFlow(
//            ndc: trimmedNdc,
//            countType: countType,
//            fallbackDrugName: trimmedDrugName
//        )
//
//        self.mannualDrugCreated = true
//    }

    
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
            self.drugName = existingDrug.drug_name ?? ""

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
        drugName: String? = nil,
        batchId: Int64? = nil,
        expirationDate: String? = nil,
        lotNumber: String? = nil,
        rxNo:String? = nil,
        bucketId: String? = nil
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
            if let path = PhotoFileManager.shared.saveImage(img) {
                savedPath = path
            } else {
                print("Failed to save image")
            }

        } else {
            print("barcodeImage is nil")
        }


        // step 2: we have got all, user id, drugId, count type, for now the barcode image is set to empty string.
        // we now call the db function to create the transaction.
        pillDataLocalStorage.createTransaction(
            for: user,
            drugId: drugId,
            countType: countType,
            batchId: batchId ?? 0,
            barcodeImagePath: savedPath,
            isComingFromPms: isComingFromPms,
            drugName: drugName,
            targetCount: targetCount,
            isControlled: isControlled,
            expirationDate: expirationDate,
            lotNumber: lotNumber,
            rxNo: rxNo,
            bucketId: bucketId
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


            if let path = PhotoFileManager.shared.saveImage(img) {
                savedPath = path
            } else {
            }

        } else {
            print("barcodeImage is nil")
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
    
    func addOrReplaceVialTransactionDetail(imagePath: String?) {
        guard let txnId = currentTransaction?.txn_id else {
            return
        }

        pillDataLocalStorage.addOrReplaceVialTransactionDetail(
            txnId: txnId,
            imagePath: imagePath
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


