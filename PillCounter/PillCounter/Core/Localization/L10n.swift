//
//  L10n.swift
//  PillCounter
//
//  Created by Bhushan Patil on 14/05/26.
//


import Foundation

enum L10n {
    
    // MARK: - Common
    enum Common {
        static let appName = NSLocalizedString("common.appName", comment: "")
        static let companyName = NSLocalizedString("common.companyName", comment: "")
        static let version = NSLocalizedString("common.version", comment: "")
        static let cancel = NSLocalizedString("common.cancel", comment: "")
        static let ok = NSLocalizedString("common.ok", comment: "")
        static let add = NSLocalizedString("common.add", comment: "")
        static let no = NSLocalizedString("common.no", comment: "")
        static let yes = NSLocalizedString("common.yes", comment: "")
        static let save = NSLocalizedString("common.save", comment: "")
        static let delete = NSLocalizedString("common.delete", comment: "")
        static let skip = NSLocalizedString("common.skip", comment: "")
        static let email = NSLocalizedString("common.email", comment: "")
        static let note = NSLocalizedString("common.note", comment: "")
        static let date = NSLocalizedString("common.date", comment: "")
        static let time = NSLocalizedString("common.time", comment: "")
        static let unselectAll = NSLocalizedString("common.unselectAll", comment: "")
        static let selectAll = NSLocalizedString("common.selectAll", comment: "")
    }
    
    // MARK: - Login
    enum Login {
        static let rememberMe = NSLocalizedString("login.rememberMe", comment: "")
        static let button = NSLocalizedString("login.button", comment: "")
        static let emailPlaceholder = NSLocalizedString("login.email.placeholder", comment: "")
        static let emailErrorEmpty = NSLocalizedString("login.email.error.empty", comment: "")
        static let emailErrorInvalid = NSLocalizedString("login.email.error.invalid", comment: "")
    }
    
    // MARK: - OTP Verification
    enum OTP {
        static let codeSentText = NSLocalizedString("otp.codeSentText", comment: "")
        static let resendCode = NSLocalizedString("otp.resendCode", comment: "")
        static let verifyButton = NSLocalizedString("otp.verifyButton", comment: "")
        static let errorInvalid = NSLocalizedString("otp.error.invalid", comment: "")
    }
    
    // MARK: - Dashboard
    enum Dashboard {
        static let completed = NSLocalizedString("dashboard.completed", comment: "")
        static let pending = NSLocalizedString("dashboard.pending", comment: "")
        
        
        // MARK: - Fixed Count
        enum FixedCount {
            static let title = NSLocalizedString("dashboard.fixedCount.title", comment: "")
            static let subtitle = NSLocalizedString("dashboard.fixedCount.subtitle", comment: "")
        }
        
        // MARK: - Regular Count
        enum RegularCount {
            static let title = NSLocalizedString("dashboard.regularCount.title", comment: "")
            static let subtitle = NSLocalizedString("dashboard.regularCount.subtitle", comment: "")
        }
        
        enum Popup {
            static let continueLastBatch = NSLocalizedString("dashboard.popup.continueLastBatch", comment: "")
            static let createNewBatch = NSLocalizedString("dashboard.popup.createNewBatch", comment: "")
            static let whatWouldYouDo = NSLocalizedString("dashboard.popup.whatWouldYouDo", comment: "")
            static let selectBucket = NSLocalizedString("dashboard.popup.selectBucket", comment: "")
        }
    }
    

    
    // MARK: - Pill Count View
    enum PillCount {
        static let total = NSLocalizedString("pillCount.total", comment: "")
        static let header = NSLocalizedString("pillCount.header", comment: "")
        static let pausedDueToInactivity = NSLocalizedString("pillCount.pausedDueToInactivity", comment: "")
        static let resume = NSLocalizedString("pillCount.resume", comment: "")
        static let confirmDeletion = NSLocalizedString("pillCount.confirmDeletion", comment: "")
        static let deleteAllTransactionsMessage = NSLocalizedString("pillCount.deleteAllTransactionsMessage", comment: "")
        static let invalidCount = NSLocalizedString("pillCount.invalidCount", comment: "")
        static let zeroPillsMessage = NSLocalizedString("pillCount.zeroPillsMessage", comment: "")
        static let confirmCompletionTitle = NSLocalizedString("pillCount.confirmCompletionTitle", comment: "")
        static let confirmCompletionMessage = NSLocalizedString("pillCount.confirmCompletionMessage", comment: "")
        static let countMismatchTitle = NSLocalizedString("pillCount.countMismatchTitle", comment: "")
        static let countMismatchMessage = NSLocalizedString("pillCount.countMismatchMessage", comment: "")
        static let confirmStepCompletionTitle = NSLocalizedString("pillCount.confirmStepCompletionTitle", comment: "")
        static let confirmStepCompletionMessage = NSLocalizedString("pillCount.confirmStepCompletionMessage", comment: "")
        static let addNote = NSLocalizedString("pillCount.addNote", comment: "")
        static let pleaseAddNote = NSLocalizedString("pillCount.pleaseAddNote", comment: "")
        static let skipStepTitle = NSLocalizedString("pillCount.skipStepTitle", comment: "")
        static let skipStepMessage = NSLocalizedString("pillCount.skipStepMessage", comment: "")
        static let totalCountExceedsTarget = NSLocalizedString("pillCount.totalCountExceedsTarget", comment: "")
        static let imageAlreadyCaptured = NSLocalizedString("pillCount.imageAlreadyCaptured", comment: "")
        static let countLessThanTarget = NSLocalizedString("pillCount.countLessThanTarget", comment: "")
        static let addButton = NSLocalizedString("pillCount.addButton", comment: "")
        static let addButtonWait = NSLocalizedString("pillCount.addButtonWait", comment: "")
        static let allDone = NSLocalizedString("pillCount.allDone", comment: "")
        static let totalCount = NSLocalizedString("pillCount.totalCount", comment: "")
        static let redo = NSLocalizedString("pillCount.redo", comment: "")
        static let done = NSLocalizedString("pillCount.done", comment: "")
        static let transactionDetail = NSLocalizedString("pillCount.transactionDetail", comment: "")
    }
    
    // MARK: - Hamburger Menu
    enum Menu {
        static let history = NSLocalizedString("menu.history", comment: "")
        static let profile = NSLocalizedString("menu.profile", comment: "")
        static let settings = NSLocalizedString("menu.settings", comment: "")
        static let logout = NSLocalizedString("menu.logout", comment: "")
        static let unsync = NSLocalizedString("menu.unsync", comment: "")
        static let confirmLogoutTitle = NSLocalizedString("menu.confirmLogoutTitle", comment: "")
        static let confirmLogoutMessage = NSLocalizedString("menu.confirmLogoutMessage", comment: "")
        static let logoutButton = NSLocalizedString("menu.logoutButton", comment: "")
        static let noLastBatchFound = NSLocalizedString("menu.toast.noLastBatchFound", comment: "")

        enum HistoryDuration {
            static let month = NSLocalizedString("menu.history.duration.month", comment: "")
            static let months = NSLocalizedString("menu.history.duration.months", comment: "")
        }
    }
    
    // MARK: - Profile
    enum Profile {
        static let firstName = NSLocalizedString("profile.firstName", comment: "")
        static let lastName = NSLocalizedString("profile.lastName", comment: "")
        static let pharmacyName = NSLocalizedString("profile.pharmacyName", comment: "")
        static let npiId = NSLocalizedString("profile.npiId", comment: "")
        static let phoneNumber = NSLocalizedString("profile.phoneNumber", comment: "")
        static let terminal = NSLocalizedString("profile.terminal", comment: "")
        static let successUpdateMessage = NSLocalizedString("profile.error.successUpdateMessage", comment: "")

        
        
        enum Popup {
            static let confirmDeleteTitle = NSLocalizedString("profile.popup.confirmDeleteTitle", comment: "")
            static let confirmDeleteMessage = NSLocalizedString("profile.popup.confirmDeleteMessage", comment: "")
        }

        enum Error {
            static let errorPhoneLengthMessage = NSLocalizedString("profile.error.errorPhoneLengthMessage", comment: "")
            static let errorPhoneDigitsMessage = NSLocalizedString("profile.error.errorPhoneDigitsMessage", comment: "")
            static let errorUpdateTerminalMessage = NSLocalizedString("profile.error.errorUpdateTerminalMessage", comment: "")
            static let errorUpdateProfileMessage = NSLocalizedString("profile.error.errorUpdateProfileMessage", comment: "")
        }
    }
    
    // MARK: - Settings
    enum Settings {
        static let alwaysAskNotes = NSLocalizedString("settings.alwaysAskNotes", comment: "")
        static let saveHistory = NSLocalizedString("settings.saveHistory", comment: "")
        static let requireDoubleCount = NSLocalizedString("settings.requireDoubleCount", comment: "")
        static let requireBackCount = NSLocalizedString("settings.requireBackCount", comment: "")
        static let requireAdjustReason = NSLocalizedString("settings.requireAdjustReason", comment: "")
        static let hapticFeedback = NSLocalizedString("settings.hapticFeedback", comment: "")
        static let soundFeedback = NSLocalizedString("settings.soundFeedback", comment: "")
        static let voiceInstructions = NSLocalizedString("settings.voiceInstructions", comment: "")
        static let clearLocalData = NSLocalizedString("settings.clearLocalData", comment: "")
        static let saveHistoryScreenTitle = NSLocalizedString("settings.saveHistoryScreenTitle", comment: "")
        static let scheduleScreenTitle = NSLocalizedString("settings.scheduleScreenTitle", comment: "")
        static let confirmHistoryTitle = NSLocalizedString("settings.confirmHistoryTitle", comment: "")
        static let confirmHistoryMessage = NSLocalizedString("settings.confirmHistoryMessage", comment: "")
        static let clearHistoryTitle = NSLocalizedString("settings.clearHistoryTitle", comment: "")
        static let clearHistoryMessage = NSLocalizedString("settings.clearHistoryMessage", comment: "")
    }

    // MARK: - Unsynced Transactions
    enum Unsync {
        static let screenTitle = NSLocalizedString("unsync.screenTitle", comment: "")
        static let allSynced = NSLocalizedString("unsync.allSynced", comment: "")
        static let pmsNotConnected = NSLocalizedString("unsync.pmsNotConnected", comment: "")
        static let stocks = NSLocalizedString("unsync.stocks", comment: "")
        static let dispenses = NSLocalizedString("unsync.dispenses", comment: "")
        static let syncAll = NSLocalizedString("unsync.syncAll", comment: "")
    }
    
    // MARK: - Camera Permission
    enum Camera {
        static let accessRequired = NSLocalizedString("camera.accessRequired", comment: "")
        static let accessMessage = NSLocalizedString("camera.accessMessage", comment: "")
        static let openSettings = NSLocalizedString("camera.openSettings", comment: "")
    }

    // MARK: - Barcode / QR Scanner
    enum BarcodeScan {
        static let batchOverlay = NSLocalizedString("barcodeScan.batchOverlay", comment: "")
        static let pillsRequired = NSLocalizedString("barcodeScan.pillsRequired", comment: "")
        static let copy = NSLocalizedString("barcodeScan.copy", comment: "")
        static let rescanRequired = NSLocalizedString("barcodeScan.rescanRequired", comment: "")
        static let ndcDoesNotMatch = NSLocalizedString("barcodeScan.ndcDoesNotMatch", comment: "")
        static let substitute = NSLocalizedString("barcodeScan.substitute", comment: "")
        static let rescan = NSLocalizedString("barcodeScan.rescan", comment: "")
        static let qrScannedSuccessfully = NSLocalizedString("barcodeScan.qrScannedSuccessfully", comment: "")
        static let labelScannedSuccessfully = NSLocalizedString("barcodeScan.labelScannedSuccessfully", comment: "")
        static let ndcNumber = NSLocalizedString("barcodeScan.ndcNumber", comment: "")
        static let drugName = NSLocalizedString("barcodeScan.drugName", comment: "")
        static let quantity = NSLocalizedString("barcodeScan.quantity", comment: "")
        static let rxNumber = NSLocalizedString("barcodeScan.rxNumber", comment: "")
        static let bucket = NSLocalizedString("barcodeScan.bucket", comment: "")
        static let selectContainerStatus = NSLocalizedString("barcodeScan.selectContainerStatus", comment: "")
        static let sealed = NSLocalizedString("barcodeScan.sealed", comment: "")
        static let opened = NSLocalizedString("barcodeScan.opened", comment: "")
        static let drugNotFound = NSLocalizedString("barcodeScan.drugNotFound", comment: "")
        static let drugNotFoundMessage = NSLocalizedString("barcodeScan.drugNotFoundMessage", comment: "")
        static let incorrectNdc = NSLocalizedString("barcodeScan.incorrectNdc", comment: "")
        static let incorrectNdcMessage = NSLocalizedString("barcodeScan.incorrectNdcMessage", comment: "")
        static let proceed = NSLocalizedString("barcodeScan.proceed", comment: "")
    }

    // MARK: - Generic Equivalent Popup
    enum GenericEquivalent {
        static let scanned = NSLocalizedString("genericEquivalent.scanned", comment: "")
        static let subtitle = NSLocalizedString("genericEquivalent.subtitle", comment: "")
        static let doYouWantSubstitute = NSLocalizedString("genericEquivalent.doYouWantSubstitute", comment: "")
    }
    
    // MARK: - History Screen
    enum History {
        static let title = NSLocalizedString("history.title", comment: "")
        static let confirmDelete = NSLocalizedString("history.confirmDelete", comment: "")
        static let pillCount = NSLocalizedString("history.pillCount", comment: "")
        static let initialContainerCount = NSLocalizedString("history.initialContainerCount", comment: "")
        static let substitutedDrugDetails = NSLocalizedString("history.substitutedDrugDetails", comment: "")
        static let requestedDrugDetails = NSLocalizedString("history.requestedDrugDetails", comment: "")
        static let dispensedDrugDetails = NSLocalizedString("history.dispensedDrugDetails", comment: "")
        static let pillRecount = NSLocalizedString("history.pillRecount", comment: "")
        static let dispensedVial = NSLocalizedString("history.dispensedVial", comment: "")
        static let remainingContainerCount = NSLocalizedString("history.remainingContainerCount", comment: "")
        static let totalCount = NSLocalizedString("history.totalCount", comment: "")
        static let substitutedDrug = NSLocalizedString("history.substitutedDrug", comment: "")
        static let drugName = NSLocalizedString("history.drugName", comment: "")
        static let ndc = NSLocalizedString("history.ndc", comment: "")
        static let expiryNo = NSLocalizedString("history.expiryNo", comment: "")
        static let lotNo = NSLocalizedString("history.lotNo", comment: "")
        static let deleteConfirmMessage = NSLocalizedString("history.deleteConfirmMessage", comment: "")
        static let noItemsToDelete = NSLocalizedString("history.noItemsToDelete", comment: "")
        static let noHistory = NSLocalizedString("history.noHistory", comment: "")
        static let noTransactionsFound = NSLocalizedString("history.noTransactionsFound", comment: "")
        static let noResults = NSLocalizedString("history.noResults", comment: "")
        static let noTransactionsMatch = NSLocalizedString("history.noTransactionsMatch", comment: "")
        static let noBatchesFound = NSLocalizedString("history.noBatchesFound", comment: "")
        static let noBatchesMatch = NSLocalizedString("history.noBatchesMatch", comment: "")
        static let filterAll = NSLocalizedString("history.filterAll", comment: "")
        static let filterCompleted = NSLocalizedString("history.filterCompleted", comment: "")
        static let filterPending = NSLocalizedString("history.filterPending", comment: "")
        static let filterDispensed = NSLocalizedString("history.filterDispensed", comment: "")
        static let filterStockCount = NSLocalizedString("history.filterStockCount", comment: "")
        static let batchIdTitle = NSLocalizedString("history.batchIdTitle", comment: "")
        static let noTransactions = NSLocalizedString("history.noTransactions", comment: "")
        static let noItemsInBatch = NSLocalizedString("history.noItemsInBatch", comment: "")
        static let totalNdcCount = NSLocalizedString("history.totalNdcCount", comment: "")
        static let completedOn = NSLocalizedString("history.completedOn", comment: "")
        static let sealedBottles = NSLocalizedString("history.sealedBottles", comment: "")
        static let openedBottles = NSLocalizedString("history.openedBottles", comment: "")
        static let deleteButton = NSLocalizedString("history.deleteButton", comment: "")
        static let okButton = NSLocalizedString("history.okButton", comment: "")
        static let unknownDrug = NSLocalizedString("history.unknownDrug", comment: "")
    }

    // MARK: - Pill Scan Detail
    enum PillScan {
        static let deleteTransaction = NSLocalizedString("pillScan.deleteTransaction", comment: "")
        static let totalCount = NSLocalizedString("pillScan.totalCount", comment: "")
        static let noScansYet = NSLocalizedString("pillScan.noScansYet", comment: "")
        static let deleteScans = NSLocalizedString("pillScan.deleteScans", comment: "")
        static let deleteScansMessage = NSLocalizedString("pillScan.deleteScansMessage", comment: "")
    }

    // MARK: - Location
    enum Location {
        static let fetching = NSLocalizedString("location.fetching", comment: "")
        static let unavailable = NSLocalizedString("location.unavailable", comment: "")
    }
    
    // MARK: - Stock
    enum Stock {
        static let confirmEndBatch = NSLocalizedString("stock.confirmEndBatch", comment: "")
        static let confirmExport = NSLocalizedString("stock.confirmExport", comment: "")
        static let endBatch = NSLocalizedString("stock.endBatch", comment: "")
        static let ndcs = NSLocalizedString("stock.ndcs", comment: "")
        static let pendingBatches = NSLocalizedString("stock.pendingBatches", comment: "")
        static let confirmDeleteTitle = NSLocalizedString("stock.confirmDeleteTitle", comment: "")
        static let deleteSelectedTitle = NSLocalizedString("stock.deleteSelectedTitle", comment: "")
        static let deleteBatchMessage = NSLocalizedString("stock.deleteBatchMessage", comment: "")
        static let deleteSelectedBatchesMessage = NSLocalizedString("stock.deleteSelectedBatchesMessage", comment: "")
        static let noTransactionsYet = NSLocalizedString("stock.noTransactionsYet", comment: "")
        static let startAddingItems = NSLocalizedString("stock.startAddingItems", comment: "")
        static let endCount = NSLocalizedString("stock.endCount", comment: "")
        static let addItem = NSLocalizedString("stock.addItem", comment: "")
        static let noCountEndBatchMessage = NSLocalizedString("stock.noCountEndBatchMessage", comment: "")
        static let addNoteQuestion = NSLocalizedString("stock.addNoteQuestion", comment: "")
        static let deleteButton = NSLocalizedString("stock.deleteButton", comment: "")
        static let cancelButton = NSLocalizedString("stock.cancelButton", comment: "")
    }
    
    // MARK: - Stock Count Sheet (bottom sheet + sub-components)
    enum StockCountSheet {
        static let batchStockCount        = NSLocalizedString("stockCountSheet.batchStockCount", comment: "")
        static let scanPills              = NSLocalizedString("stockCountSheet.scanPills", comment: "")
        static let recentBatchCount       = NSLocalizedString("stockCountSheet.recentBatchCount", comment: "")
        static let noItemsAddedYet        = NSLocalizedString("stockCountSheet.noItemsAddedYet", comment: "")
        static let scannedDrugDetails     = NSLocalizedString("stockCountSheet.scannedDrugDetails", comment: "")
        static let scannedSummary         = NSLocalizedString("stockCountSheet.scannedSummary", comment: "")
        static let scanNewStockBottle     = NSLocalizedString("stockCountSheet.scanNewStockBottle", comment: "")
        static let totalNdcs              = NSLocalizedString("stockCountSheet.totalNdcs", comment: "")
        static let totalPills             = NSLocalizedString("stockCountSheet.totalPills", comment: "")
        static let pills                  = NSLocalizedString("stockCountSheet.pills", comment: "")
        static let bottles                = NSLocalizedString("stockCountSheet.bottles", comment: "")
        static let sealedBottles          = NSLocalizedString("stockCountSheet.sealedBottles", comment: "")
        static let openedBottles          = NSLocalizedString("stockCountSheet.openedBottles", comment: "")
        static let editDetails            = NSLocalizedString("stockCountSheet.editDetails", comment: "")
        static let drugName               = NSLocalizedString("stockCountSheet.drugName", comment: "")
        static let ndcNumber              = NSLocalizedString("stockCountSheet.ndcNumber", comment: "")
        static let bucket                 = NSLocalizedString("stockCountSheet.bucket", comment: "")
        static let batchNo                = NSLocalizedString("stockCountSheet.batchNo", comment: "")
        static let expiryDate             = NSLocalizedString("stockCountSheet.expiryDate", comment: "")
        static let openPills              = NSLocalizedString("stockCountSheet.openPills", comment: "")
        static let lotNumber              = NSLocalizedString("stockCountSheet.lotNumber", comment: "")
        static let total                  = NSLocalizedString("stockCountSheet.total", comment: "")
        static let clear                  = NSLocalizedString("stockCountSheet.clear", comment: "")
        static let add                    = NSLocalizedString("stockCountSheet.add", comment: "")
        static let edit                   = NSLocalizedString("stockCountSheet.edit", comment: "")
        static let pillsWithCount         = NSLocalizedString("stockCountSheet.pillsWithCount", comment: "")

        static func recentBatchCountWithN(_ n: Int) -> String {
            String(format: NSLocalizedString("stockCountSheet.recentBatchCountWithN", comment: ""), n)
        }
    }

    // MARK: - Stock Count Partial Batch List
     enum StockCountBatchList {
         static let pendingBatches = NSLocalizedString("stockCountBatchList.pendingBatches", comment: "")
         static let confirmDeleteTitle = NSLocalizedString("stockCountBatchList.confirmDeleteTitle", comment: "")
         static let deleteSelectedTitle = NSLocalizedString("stockCountBatchList.deleteSelectedTitle", comment: "")
         static let deleteBatchMessage = NSLocalizedString("stockCountBatchList.deleteBatchMessage", comment: "")
         static let deleteSelectedBatchesMessage = NSLocalizedString("stockCountBatchList.deleteSelectedBatchesMessage", comment: "")
         static func batchPrefix(_ id: String) -> String {
             String(format: NSLocalizedString("stockCountBatchList.batchPrefix", comment: ""), id)
         }
     }
  
     // MARK: - Stock Count Batch Detail
     enum StockCountBatchDetail {
         static let deleteButton = NSLocalizedString("stockCountBatchDetail.deleteButton", comment: "")
         static let cancelButton = NSLocalizedString("stockCountBatchDetail.cancelButton", comment: "")
         static let noTransactionsYet = NSLocalizedString("stockCountBatchDetail.noTransactionsYet", comment: "")
         static let startAddingItems = NSLocalizedString("stockCountBatchDetail.startAddingItems", comment: "")
         static let endCount = NSLocalizedString("stockCountBatchDetail.endCount", comment: "")
         static let addItem = NSLocalizedString("stockCountBatchDetail.addItem", comment: "")
         static let confirmEndBatch = NSLocalizedString("stockCountBatchDetail.confirmEndBatch", comment: "")
         static let noCountEndBatchMessage = NSLocalizedString("stockCountBatchDetail.noCountEndBatchMessage", comment: "")
         static let confirmExport = NSLocalizedString("stockCountBatchDetail.confirmExport", comment: "")
         static let addNoteQuestion = NSLocalizedString("stockCountBatchDetail.addNoteQuestion", comment: "")
         static let pleaseAddNote = NSLocalizedString("stockCountBatchDetail.pleaseAddNote", comment: "")
         static let skip = NSLocalizedString("stockCountBatchDetail.skip", comment: "")
  
         static func batchIdTitle(_ id: Int64) -> String {
             String(format: NSLocalizedString("stockCountBatchDetail.batchIdTitle", comment: ""), id)
         }
     }
    

    enum DispensePartial {

        enum Filter {
            static let all = NSLocalizedString("dispensePartial.filter.all", comment: "")
            static let pms = NSLocalizedString("dispensePartial.filter.pms", comment: "")
            static let nonPms = NSLocalizedString("dispensePartial.filter.nonPms", comment: "")
        }

        enum Dialog {
            static let confirmDeleteTitle = NSLocalizedString("dispensePartial.dialog.confirmDeleteTitle", comment: "")
            static let deleteSelectedTitle = NSLocalizedString("dispensePartial.dialog.deleteSelectedTitle", comment: "")

            static let deleteTransactionMessage = NSLocalizedString("dispensePartial.dialog.deleteTransactionMessage", comment: "")
            static let deleteSelectedTransactionsMessage = NSLocalizedString("dispensePartial.dialog.deleteSelectedTransactionsMessage", comment: "")
        }
    }
    
    enum GenericList {
        static let deleteBatches = NSLocalizedString("genericList.deleteBatches", comment: "")
        static let noPendingCountsAvailable = NSLocalizedString("genericList.noPendingCountsAvailable", comment: "")
        static let noResultsFound = NSLocalizedString("genericList.noResultsFound", comment: "")
    }
    
    // MARK: - Controlled Step
    enum Controlled {
        static let scan = NSLocalizedString("controlled.scan", comment: "")
        static let containerInitiate = NSLocalizedString("controlled.containerInitiate", comment: "")
        static let targetVerification = NSLocalizedString("controlled.targetVerification", comment: "")
        static let targetReverification = NSLocalizedString("controlled.targetReverification", comment: "")
        static let vial = NSLocalizedString("controlled.vial", comment: "")
        static let containerPending = NSLocalizedString("controlled.containerPending", comment: "")
        static let regularTargetReverification = NSLocalizedString("controlled.regularTargetReverification", comment: "")
        static let scanBarcode = NSLocalizedString("controlled.scanBarcode", comment: "")
        static let scanStockCountBarcode = NSLocalizedString("controlled.scanStockCountBarcode", comment: "")
        static let scanRxLabelBarcode = NSLocalizedString("controlled.scanRxLabelBarcode", comment: "")
    }
}
