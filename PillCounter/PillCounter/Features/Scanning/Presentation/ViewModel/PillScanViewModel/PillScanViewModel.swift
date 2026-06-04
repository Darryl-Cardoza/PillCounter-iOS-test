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

    // DAO instances
    let drugMasterDAO = DrugCatalogStore.shared
    let transactionDAO = TransactionStore.shared
    let transactionDetailDAO = TransactionDetailStore.shared
    let batchDAO = BatchStore.shared
    let userDataLocalStorage = UserStore.shared

    // decode the values of the barcode or qr, calling the api, processing it, storing it in database
    let decoder = BarcodeAndQRDecoder()
    let userRepo = UserRepository.shared

    @Published var isDrugFound: Bool?

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
    var userId: String { AppStorageManager.shared.userId ?? "" }
        
    private var cancellables = Set<AnyCancellable>()
    
    //Controlled Drug Repository
    let controlledRepo  = ControlledRepository.shared

    //Toast
    @Published  var showToast: Bool = false
    @Published  var toastMessage: String = ""
    @Published  var toastAutoClose: Bool = true

    // To Manager Controlled Drug Step
    @Published var currentControlledStep: ControlledStep = .scan
    @Published var currentControlledTargetCount: Int? = nil
    @Published var showCompletionPopup = false

    // MARK: Controlled drug Equivalence
    @Published var isCheckingNdc: Bool = false
    @Published var ndcComparisonResponse: NdcComparisonResponse?
    @Published var isNdcEquivalent: Bool = false
    @Published var showNdcEquivalencePopup = false
    @Published var ndcMismatchRestartFlow = false
    @Published var shouldAutoProceedToCount = false
    @Published var isNdcAdded: Bool = false
    
    // MARK: Stock Count State
    @Published var addCurrentOpenPillCount: Int = 0

    // Set to true before pushing to PillScanDetailGridScreen so onDisappear
    // in PillCountView knows not to clear transaction data mid-push.
    var isNavigatingToDetailGrid: Bool = false

    // MARK: Vial Step State
    @Published var capturedVialImage: UIImage? = nil
    @Published var vialCapturedImagePath: String? = nil
    @Published var vialDoneTriggered: Bool = false

    //MARK: RX FLow
    @Published var showRxFlowPopup: Bool = false
    @Published var showRxOnHoldPopup: Bool = false
    @Published var rxScanFailed: Bool = false
    @Published var scannedRxData: ParsedScanData? = nil
    @Published var bucketOptions: [String] = []
    @Published var selectedBucket: String = ""
    @Published var showScannedDrugInfoPopoup: Bool = false
    
    
    private func postTransactionUIUpdate(countType: CountType) {
        getAllTransactionDetailsOfTheCurrentTransaction()

        if countType == .FIXED {
            updateTargetCountForCurrentTransaction()
        }

        isDrugFound = true
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
        bucketId: String? = nil,
        priority: String? = nil,
        workFlowStep: String? = nil
    ) async {
        // creating the transaction for the pill.
        // step1: get the user.
        guard
            !userId.isEmpty,
            let user = userDataLocalStorage.fetchByUserId(userId)
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
        transactionDAO.create(
            for: user,
            drugId: drugId,
            countType: countType,
            batchId: batchId ?? 0,
            barcodeImagePath: savedPath,
            isFromPms: isComingFromPms,
            drugName: drugName,
            targetCount: targetCount ?? 0,
            isControlled: isControlled,
            expirationDate: expirationDate,
            lotNumber: lotNumber,
            rxNo: rxNo,
            bucketId: bucketId,
            priority: priority,
            workFlowStep: workFlowStep
        )


        // step 3: set the latest transaction as current transaction.
        if let latest = transactionDAO.fetchLatest(for: user) {
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
            let user = userDataLocalStorage.fetchByUserId(userId)
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
        transactionDAO.update(
            txnId: txnId,
            drugId: drugId,
            countType: countType,
            targetCount: targetCount,
            barcodeImagePath: savedPath
        )

        // step 3: set the latest transaction as current transaction.
        if let latest = transactionDAO.fetchLatest(for: user) {
            self.currentTransaction = latest
        }

    }

    
    func getAllTransactionDetailsOfTheCurrentTransaction() {
        guard let txnId = currentTransaction?.txn_id else { return }
        currentTransactionTransactionDetails =
            transactionDetailDAO.fetchForStep(
                txnId: txnId,
                step: currentControlledStep
            )
    }
    
    func addOrReplaceVialTransactionDetail(imagePath: String?) {
        guard let txnId = currentTransaction?.txn_id else {
            return
        }

        transactionDetailDAO.addOrReplaceVial(txnId: txnId, imagePath: imagePath)
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

        transactionDetailDAO.add(
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

        transactionDAO.updateTargetCount(txnId: txnId, targetCount: targetValue)

        // update the current transaction for updating the ui.
        if let updatedTxn = transactionDAO.fetchById(txnId) {
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
        transactionDAO.updateNote(txnId: txn_id, note: note)
    }


    func getCurrentTransaction(txnId: Int64) async {
        // Fetch transaction
        currentTransaction = transactionDAO.fetchById(txnId)

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
        transactionDetailDAO.update(detailId: txnDetailId) { transactionDetails in
            transactionDetails.is_deleted = true
        }

        getAllTransactionDetailsOfTheCurrentTransaction()
    }
    
    
    func deleteAllDetailsOfCurrentTransaction() {
        guard let txnId = currentTransaction?.txn_id else {
            return
        }

        transactionDetailDAO.softDeleteForStep(txnId: txnId, step: currentControlledStep)

        // Refresh in-memory state to update UI
        getAllTransactionDetailsOfTheCurrentTransaction()
    }

    func resetScanningState() {
        self.isDrugFound = nil
        self.currentTransaction = nil
        self.currentTransactionTransactionDetails = nil
        self.targetCount = ["", "", "", ""]
        self.isCheckingNdc = false
    }
 
    
    // Message handling for transaction coming from pms
    typealias HL7SimpleCallback = (Bool) -> Void
    
    //ShowToastMessage
    func showToastMessage(text: String, autoClose: Bool = true) {
        toastMessage = text
        toastAutoClose = autoClose
        showToast = true

        guard autoClose else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.showToast = false
        }
    }

 
    
    // MARK: - HARD LOGOUT RESET
    @MainActor
    func resetState() {
        cancellables.removeAll()
        isDrugFound = nil
        targetCount = ["", "", "", ""]
        note = ""
        currentTransaction = nil
        currentTransactionTransactionDetails = nil
        selectedTransaction = nil
        showNdcEquivalencePopup = false
        isCheckingNdc = false
        isNdcEquivalent = false
        ndcComparisonResponse = nil
    }
}
