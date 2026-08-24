//
//  PillScanViewModel.swift
//  PillCounter
//
//  Created by HC on 17/11/25.
//

import Foundation
import SwiftUI
import Hl7Core
import Combine

@MainActor
class PillScanViewModel: ObservableObject {

    // Injected dependencies — default to production singletons so existing
    // call sites (`PillScanViewModel()`) keep working; tests pass mocks.
    let drugMasterDAO: DrugCatalogDataSource
    let transactionDAO: TransactionDataSource
    let transactionDetailDAO: TransactionDetailDataSource
    let batchDAO: BatchDataSource
    let stockTxnDAO: StockTxnDataSource
    let bottleInfoDAO: BottleInfoDataSource
    let userDataLocalStorage: UserDataSource
    let decoder: BarcodeAndQRDecoder
    let userRepo: UserRepositoryProtocol

    @Published var isDrugFound: Bool?

    /// Filename of the barcode image saved for the scan currently being confirmed
    /// (set by `updateSubstitutedDrug`/`createTransaction`/`updaetTransaction` right
    /// after saving to disk). Consumed once by `stageFirstBottleIfNeeded` after NDC
    /// verification lands, so the first `BottleInfo` gets the same image without
    /// saving it to disk a second time.
    var pendingBarcodeImagePath: String?

    // set the target count for fixed or dispense count
    @Published var targetCount: [String] = Array(repeating: "", count: 4)

    // this will hold the current scanning transaction that user is performing or working with.
    // Only used by the regular (non-StockCount) FIXED/REGULAR dispense-counting flow.
    @Published var currentTransaction: PillCountTransactionEntity?

    // Stock-count equivalents of currentTransaction — one NDC row (currentStockTxn) plus the
    // specific BottleInfoEntity row (currentBottleInfo) written by the most recent scan.
    @Published var currentStockTxn: StockTxnEntity?
    @Published var currentBottleInfo: BottleInfoEntity?

    /// Lot/expiry/serial from the barcode scanned to start an open-pill count.
    /// No BottleInfoEntity row is written until the count is confirmed (Proceed) —
    /// see `createOpenedBottleFromPendingScan`.
    var pendingOpenBottleLot: String?
    var pendingOpenBottleExpiry: String?
    var pendingOpenBottleSerial: String?

    /// Resolved NDC/drug/batch identity for an open-pill scan, held in memory only.
    /// No BatchCountEntity or StockTxnEntity is created until the count is confirmed
    /// (Proceed) — see `createOpenedBottleFromPendingScan`. This lets the header/UI
    /// show the scanned drug immediately without persisting anything for a count the
    /// user might abandon (back out / kill the app before finishing).
    @Published var pendingOpenBottleDrug: DrugMasterEntity?
    var pendingOpenBottleDrugId: Int64?
    var pendingOpenBottleBucketId: String?

    /// Drug for whichever flow is active — FIXED/REGULAR dispense (currentTransaction),
    /// stock-count open-pill counting with a persisted StockTxn (currentStockTxn), or an
    /// open-pill scan still pending confirmation (pendingOpenBottleDrug).
    var currentDrug: DrugMasterEntity? {
        currentTransaction?.drug ?? currentStockTxn?.drug ?? pendingOpenBottleDrug
    }

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
    let controlledRepo: ControlledRepositoryProtocol

    // MARK: - Init
    init(
        drugMasterDAO: DrugCatalogDataSource = DrugCatalogStore.shared,
        transactionDAO: TransactionDataSource = TransactionStore.shared,
        transactionDetailDAO: TransactionDetailDataSource = TransactionDetailStore.shared,
        batchDAO: BatchDataSource = BatchStore.shared,
        stockTxnDAO: StockTxnDataSource = StockTxnStore.shared,
        bottleInfoDAO: BottleInfoDataSource = BottleInfoStore.shared,
        userDataLocalStorage: UserDataSource = UserStore.shared,
        decoder: BarcodeAndQRDecoder = BarcodeAndQRDecoder(),
        userRepo: UserRepositoryProtocol = UserRepository.shared,
        controlledRepo: ControlledRepositoryProtocol = ControlledRepository.shared
    ) {
        self.drugMasterDAO = drugMasterDAO
        self.transactionDAO = transactionDAO
        self.transactionDetailDAO = transactionDetailDAO
        self.batchDAO = batchDAO
        self.stockTxnDAO = stockTxnDAO
        self.bottleInfoDAO = bottleInfoDAO
        self.userDataLocalStorage = userDataLocalStorage
        self.decoder = decoder
        self.userRepo = userRepo
        self.controlledRepo = controlledRepo
    }

    //Toast
    @Published  var showToast: Bool = false
    @Published  var toastMessage: String = ""
    @Published  var toastAutoClose: Bool = true

    // Hazardous tray
    @Published  var showHazardousTrayPopup: Bool = false
    @Published  var pendingHazardousTrayColor: String = ""
    /// Shown when a hazardous-drug txn is counted on a tray whose colour doesn't
    /// match the stored hazardous tray. Offers to substitute the stored colour
    /// with the currently-detected one.
    @Published  var showHazardousTraySubstitutePopup: Bool = false

    /// The tray colour we last surfaced a toast for, so the continuous flow only
    /// re-toasts when the colour actually CHANGES (not every emission). Reset when
    /// a new scan session begins.
    private var lastToastedTrayColor: String? = nil

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

    // MARK: Multi-bottle tracking (dispense-only)
    @Published var showAddBottlePopup: Bool = false
    @Published var showReplaceBottlePopup: Bool = false
    var pendingBottleRescan: BottleInfo?
    var isProcessingBottleRescan: Bool = false
    /// Snapshot captured at the moment the barcode was detected — used for the
    /// confirmation popup instead of re-capturing at confirm-tap time, so a camera
    /// move while the popup is up can't swap in the wrong frame.
    var pendingBottleRescanImage: UIImage?

    // MARK: Stock Count State
    @Published var addCurrentOpenPillCount: Int = 0

    // Set to true before pushing to PillScanDetailGridScreen so onDisappear
    // in PillCountView knows not to clear transaction data mid-push.
    var isNavigatingToDetailGrid: Bool = false

    // MARK: Vial Step State
    @Published var capturedVialImage: UIImage? = nil
    @Published var vialCapturedImagePath: String? = nil
    @Published var vialDoneTriggered: Bool = false
    /// Toggled briefly when a vial still is captured to drive the white shutter
    /// flash animation in UnifiedCameraLayout.
    @Published var vialCaptureFlash: Bool = false

    //MARK: RX FLow
    @Published var showRxFlowPopup: Bool = false
    @Published var showRxOnHoldPopup: Bool = false
    @Published var showRxInProgressPopup: Bool = false
    @Published var rxResumeInline: Bool = false
    @Published var rxScanFailed: Bool = false
    @Published var scannedRxData: ParsedScanData? = nil
    @Published var fetchedRxTransaction: PillCountTransactionEntity? = nil
    @Published var bucketOptions: [String] = []
    @Published var selectedBucket: String = ""
    @Published var showScannedDrugInfoPopoup: Bool = false
    /// Hazardous-drug confirmation sheet shown when the scanned bottle matches the
    /// expected (same) drug AND that drug is hazardous. Proceed continues the flow.
    @Published var showVerifyStockBottlePopup: Bool = false

    
    // MARK: - Dispense-count entry

    /// Sets up the shared scan session for an existing dispense transaction,
    /// fetched fresh from the store by id. Centralises the setup that callers
    /// (dashboard, history lists, sheets) previously duplicated inline.
    /// Returns the derived count type + scan type so the caller can route, or
    /// nil if the transaction no longer exists.
    @discardableResult
    func startDispenseCount(txnId: Int64) -> (isDispense: Bool, scanType: ScanType)? {
        guard let txn = transactionDAO.fetchById(txnId) else { return nil }

        selectedTransaction = txn

        let isDispense = txn.is_dispense
        let scanType: ScanType = txn.is_ndc_verfied ? .resumeCount : .barcode

        return (isDispense, scanType)
    }

    private func postTransactionUIUpdate(isDispense: Bool) {
        getAllTransactionDetailsOfTheCurrentTransaction()

        if isDispense {
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
        drugId: Int64, isDispense: Bool,
        barcodeImage: UIImage? = nil,
        isComingFromPms:Bool = false,
        isControlled:Bool? = nil,
        targetCount: Int32? = nil,
        drugName: String? = nil,
        batchId: Int64? = nil,
        rxNo:String? = nil,
        bucketId: String? = nil,
        priority: String? = nil,
        workFlowStep: String? = nil,
        refillNo: String? = nil
    ) async {
        // creating the transaction for the pill.
        // step1: get the user.
        guard
            !userId.isEmpty,
            let user = userDataLocalStorage.fetchByUserId(userId)
        else {
            return
        }

        // Save Image using Helper if it exists; stashed for stageFirstBottleIfNeeded
        // to attach to the transaction's first BottleInfo once NDC-verified.
        if let img = barcodeImage {
            pendingBarcodeImagePath = PhotoFileManager.shared.saveImage(img)
        }

        // step 2: we have got all, user id, drugId, count type.
        // we now call the db function to create the transaction.
        transactionDAO.create(
            for: user,
            drugId: drugId,
            isDispense: isDispense,
            batchId: batchId ?? 0,
            isFromPms: isComingFromPms,
            drugName: drugName,
            targetCount: targetCount ?? 0,
            isControlled: isControlled,
            rxNo: rxNo,
            bucketId: bucketId,
            priority: priority,
            workFlowStep: workFlowStep,
            refillNo: refillNo
        )


        // step 3: set the latest transaction as current transaction.
        if let latest = transactionDAO.fetchLatest(for: user) {
            self.currentTransaction = latest
        }
    }
    
    func updaetTransaction(
        drugId: Int64,
        isDispense: Bool,
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

        // Save Image using Helper if it exists; stashed for stageFirstBottleIfNeeded
        // to attach to the transaction's first BottleInfo once NDC-verified.
        if let img = barcodeImage {
            pendingBarcodeImagePath = PhotoFileManager.shared.saveImage(img)
        }

        // step 2: we have got all, user id, drugId, count type.
        // we now call the db function to update the transaction.
        transactionDAO.update(
            txnId: txnId,
            drugId: drugId,
            isDispense: isDispense,
            targetCount: targetCount
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

        let detail = transactionDetailDAO.add(
            txnId: txnId,
            pillCount: pillCount,
            imagePath: imagePath,
            type: type,
            isManual: isManual
        )

        if currentTransaction?.is_dispense == true, let detailId = detail?.txn_details_id {
            var bottles = transactionDAO.getBottleList(txnId: txnId)
            if !bottles.isEmpty {
                bottles[bottles.count - 1].txnDetailsIds.append(detailId)
                transactionDAO.setBottleList(txnId: txnId, bottles)
            }
        }

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

    func updateGlovesDetected(detected: Bool) {
        guard let txnId = currentTransaction?.txn_id else { return }
        transactionDAO.updateGlovesDetected(txnId: txnId, detected: detected)
        currentTransaction?.gloves_detected = detected
    }

    func updateHazardousTrayDetected(detected: Bool) {
        guard let txnId = currentTransaction?.txn_id else { return }
        print("🧪 [HazardousTray] updateHazardousTrayDetected txnId=\(txnId) detected=\(detected)")
        transactionDAO.updateHazardousTrayDetected(txnId: txnId, detected: detected)
        currentTransaction?.hazardous_tray_detected = detected
    }

    // MARK: - Hazardous tray flow

    /// Called whenever the camera detects a CHANGE in the visible tray's colour
    /// during pill counting. Branches on whether the current drug is hazardous and
    /// whether we already have a stored hazardous tray colour. Because the camera
    /// only emits on colour change, this fires once per distinct tray.
    func handleTrayColorDetected(_ color: TrayColor, drugIsHazardous: Bool) {
        // While a hazardous-tray popup is up, freeze on the pending colour — ignore
        // any further colour changes so the operator confirms exactly what they saw.
        guard !showHazardousTrayPopup, !showHazardousTraySubstitutePopup else { return }

        let detectedName = color.displayName
        let storedName = AppStorageManager.shared.hazardousTrayColor

        print("🧪 [HazardousTray] detected=\(detectedName) stored=\(storedName ?? "nil") drugIsHazardous=\(drugIsHazardous) txnDetected=\(currentTransaction?.hazardous_tray_detected == true)")

        if drugIsHazardous {
            if storedName == nil {
                // First-ever capture: ask the operator to confirm (once ever).
                // Pause colour detection so the live feed can't change the pending
                // colour underneath the popup; resumed on confirm/dismiss.
                print("🧪 [HazardousTray] No stored colour — prompting capture for \(detectedName)")
                pendingHazardousTrayColor = detectedName
                showHazardousTrayPopup = true
            } else if storedName == detectedName {
                // Correct hazardous tray — mark the transaction.
                print("🧪 [HazardousTray] Correct hazardous tray (\(detectedName)) — marking txn detected=true")
                updateHazardousTrayDetected(detected: true)
            } else {
                // Wrong tray in a hazardous flow: instead of prompting to substitute
                // the stored hazardous tray colour, just surface a toast that a
                // different tray was detected. The substitute popup flow is kept
                // commented out below in case we need to restore it.
                print("🧪 [HazardousTray] Wrong tray: got \(detectedName), expected \(storedName ?? "") — toast only")
                pendingHazardousTrayColor = detectedName
                showToastMessage(text: "Wrong tray. Use the saved \(storedName ?? "") tray for hazardous drugs.")
                // Only flag NOT-detected if it isn't already confirmed true —
                // once a txn is marked hazardous-tray-detected it stays true.
                if currentTransaction?.hazardous_tray_detected != true {
                    updateHazardousTrayDetected(detected: false)
                }

                // ── Previous substitute-popup flow (kept for reference) ──────────
                // pendingHazardousTrayColor = detectedName
                // showHazardousTraySubstitutePopup = true
                // if currentTransaction?.hazardous_tray_detected != true {
                //     updateHazardousTrayDetected(detected: false)
                // }
            }
        } else {
            // Non-hazardous flow: only warn when using the stored hazardous tray.
            // Toast once per distinct colour — re-toast only when the colour changes.
            // Never write hazardous_tray_detected here (hazardous drug only).
            if storedName == detectedName, lastToastedTrayColor != detectedName {
                lastToastedTrayColor = detectedName
                print("🧪 [HazardousTray] Non-hazardous drug on hazardous tray (\(detectedName)) — warning")
                showToastMessage(text: "The \(detectedName) tray is reserved for hazardous drugs. Please use a different tray.")
            } else if storedName != detectedName {
                // Reset so returning to the hazardous tray re-toasts.
                lastToastedTrayColor = detectedName
            }
        }
    }

    /// Clears the per-session tray-toast tracker. Call when a new scan session
    /// begins so the first tray of the new session can toast again.
    func resetTrayColorTracking() {
        lastToastedTrayColor = nil
    }

    /// Operator tapped "Yes" on the hazardous-tray confirmation popup.
    func confirmHazardousTray() {
        AppStorageManager.shared.hazardousTrayColor = pendingHazardousTrayColor
        updateHazardousTrayDetected(detected: true)
        showHazardousTrayPopup = false
    }

    /// Operator tapped "No" — keep nothing.
    func dismissHazardousTrayPopup() {
        showHazardousTrayPopup = false
    }

    /// Operator tapped "Substitute" on the wrong-tray popup — replace the stored
    /// hazardous tray colour with the currently-detected one and mark the txn.
    func substituteHazardousTray() {
        AppStorageManager.shared.hazardousTrayColor = pendingHazardousTrayColor
        updateHazardousTrayDetected(detected: true)
        showHazardousTraySubstitutePopup = false
    }

    /// Operator dismissed the wrong-tray popup without substituting.
    func dismissHazardousTraySubstitutePopup() {
        showHazardousTraySubstitutePopup = false
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
    // Single source of truth: routes every scanning toast through the global
    // ToastManager so only one toast ever shows app-wide. The old local toast in
    // UnifiedCameraLayout has been removed.
    func showToastMessage(text: String, autoClose: Bool = true) {
        ToastManager.shared.show(message: text, duration: autoClose ? 4 : 8)
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
