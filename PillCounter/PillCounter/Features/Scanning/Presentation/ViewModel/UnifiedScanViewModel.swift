//
//  UnifiedScanViewModel.swift
//  PillCounter
//

import Foundation
import SwiftUI
import Combine
import ComposeApp

@MainActor
class UnifiedScanViewModel: ObservableObject {

    // MARK: - Repository
    private let repo: PillScanRepository

    init(repo: PillScanRepository = PillScanRepositoryImpl.shared) {
        self.repo = repo
    }

    // MARK: - Decoder
    let decoder = BarcodeAndQRDecoder()

    // MARK: - Drug State
    @Published var drugName: String? = nil
    @Published var isDrugFound: Bool? = nil
    @Published var drugNameMannuallyEntered: String = ""
    @Published var ndcNumber: String = ""
    @Published var mannualDrugCreated: Bool? = nil

    // MARK: - Transaction State
    @Published var currentTransaction: PillCountTransactionEntity? = nil
    @Published var currentTransactionDetails: [PillCountTransactionDetailsEntity] = []
    // alias matching old ViewModel property name — for drop-in replacement
    var currentTransactionTransactionDetails: [PillCountTransactionDetailsEntity]? {
        get { currentTransactionDetails.isEmpty ? nil : currentTransactionDetails }
        set { currentTransactionDetails = newValue ?? [] }
    }
    @Published var selectedTransaction: PillCountTransactionEntity? = nil
    @Published var targetCount: [String] = Array(repeating: "", count: 4)
    @Published var note: String = ""
    @Published var addCurrentOpenPillCount: Int = 0
    var isNavigatingToDetailGrid: Bool = false

    // MARK: - Toast
    @Published var showToast: Bool = false
    @Published var toastMessage: String = ""

    // MARK: - Controlled Drug
    @Published var currentControlledStep: ControlledStep = .scan
    @Published var currentControlledTargetCount: Int? = nil
    @Published var showCompletionPopup: Bool = false

    // MARK: - NDC Equivalence
    @Published var isCheckingNdc: Bool = false
    @Published var ndcComparisonResponse: NdcComparisonResponse? = nil
    @Published var isNdcEquivalent: Bool = false
    @Published var showNdcEquivalencePopup: Bool = false
    @Published var isNdcAdded: Bool = false
    @Published var shouldAutoProceedToCount: Bool = false

    // MARK: - RX Flow
    @Published var showRxFlowPopup: Bool = false
    @Published var scannedRxData: ParsedScanData? = nil
    @Published var bucketOptions: [String] = []
    @Published var selectedBucket: String = ""
    @Published var showScannedDrugInfoPopoup: Bool = false

    // MARK: - Stock Count

    func createTxnForBatchFromScan(
        rawValueFromBarcodeOrQr: String?,
        ndc: String,
        drugName: String,
        quantity: Int32,
        countType: CountType,
        batchId: Int64,
        containerStatus: StockCountOptionContainerStatus,
        image: UIImage? = nil
    ) async {
        guard !ndc.isEmpty else { return }

        let decoded = decoder.decode(rawValueFromBarcodeOrQr ?? "")
        let gtin = decoded.gtin ?? ""
        let expiryString = formatExpiry(decoded.expirationDate)

        // 1. Check existing txn in batch
        let existingTxn = repo.fetchTransactionsByBatch(batchId: batchId).first {
            $0.drug?.ndc == ndc &&
            $0.drug?.package_qty == quantity &&
            $0.is_deleted == false &&
            $0.expiry == expiryString &&
            $0.lot_no == decoded.lotNumber
        }

        if let txn = existingTxn {
            repo.updateCounts(
                txnId: txn.txn_id,
                bottleQty: containerStatus == .sealed ? 1 : nil,
                looseQty: containerStatus == .opened ? 0 : nil
            )
            currentTransaction = repo.fetchTransaction(txnId: txn.txn_id)
            handlePostScanUI(containerStatus: containerStatus)
            return
        }

        // 2. Resolve or create drug
        guard let drug = await repo.resolveOrCreateDrugForStock(
            ndc: ndc, gtin: gtin, drugName: drugName, quantity: quantity
        ) else { return }

        // 3. Create transaction
        currentTransaction = await repo.createTransaction(
            drugId: drug.drug_id, countType: countType, barcodeImage: image,
            isFromPms: false, isControlled: nil, targetCount: nil,
            drugName: drugName, batchId: batchId, expirationDate: expiryString,
            lotNumber: decoded.lotNumber, rxNo: nil, bucketId: nil
        )

        // 4. Set initial counts on newly created txn
        guard let latestTxn = repo.fetchTransactionsByBatch(batchId: batchId)
            .filter({ $0.is_deleted == false })
            .max(by: { $0.txn_id < $1.txn_id }) else { return }

        repo.updateCounts(
            txnId: latestTxn.txn_id,
            bottleQty: containerStatus == .sealed ? 1 : nil,
            looseQty: containerStatus == .opened ? 0 : nil
        )
        currentTransaction = repo.fetchTransaction(txnId: latestTxn.txn_id)
        handlePostScanUI(containerStatus: containerStatus)
    }

    func updatePmsTxnCount(
        txn: PillCountTransactionEntity,
        containerStatus: StockCountOptionContainerStatus,
        scannedQty: Int
    ) {
        let currentBottle = Int32(txn.bottle_qty)
        let currentLoose = Int32(txn.loose_qty)

        switch containerStatus {
        case .sealed:
            repo.updateCounts(txnId: txn.txn_id, bottleQty: currentBottle + 1, looseQty: currentLoose)
        case .opened:
            repo.updateCounts(txnId: txn.txn_id, bottleQty: currentBottle, looseQty: currentLoose + Int32(scannedQty))
        }
        handlePostScanUI(containerStatus: containerStatus)
    }

    @MainActor
    func createBatchAndTxnsFromHL7Request(medications: [MedicationData], requestId: String, bucketId: String?) async {
        guard !medications.isEmpty else { return }

        struct ResolvedItem {
            let drugId: Int64
            let resolvedName: String
        }

        var resolvedItems: [ResolvedItem] = []

        for med in medications {
            let ndc = med.drugCode
            guard !ndc.isEmpty else { continue }

            if let existing = DrugMasterDAO.shared.fetchByNdc(ndc),
               let name = existing.drug_name, !name.isEmpty {
                resolvedItems.append(ResolvedItem(drugId: existing.drug_id, resolvedName: name))
                continue
            }

            do {
                let response = try await ControlledRepository.shared.getControlledDrugInfo(
                    ndcValidationRequest: NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)
                )
                guard let lookup = response.data?.scannedNdc?.lookupName, !lookup.isEmpty else { continue }
                let newId = generateUniqueDrugId()
                DrugMasterDAO.shared.fetchOrCreate(ndc: response.data?.scannedNdc?.packageNdc ?? "", drugId: newId)
                DrugMasterDAO.shared.update(
                    drugId: newId,
                    drugName: lookup,
                    drugType: response.data?.scannedNdc?.deaSchedule,
                    packageQty: response.data?.scannedNdc?.safeQuantity ?? 0
                )
                resolvedItems.append(ResolvedItem(drugId: newId, resolvedName: lookup))
            } catch {
                continue
            }
        }

        guard !resolvedItems.isEmpty else { return }

        guard let batch = repo.createBatch(bucketId: bucketId ?? "", requestId: requestId) else { return }

        for item in resolvedItems {
            _ = await repo.createTransaction(
                drugId: item.drugId, countType: .REGULAR, barcodeImage: nil,
                isFromPms: true, isControlled: nil, targetCount: 0,
                drugName: item.resolvedName, batchId: batch.batch_id,
                expirationDate: nil, lotNumber: nil, rxNo: nil, bucketId: bucketId
            )
        }
    }

    func formatExpiry(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func handlePostScanUI(containerStatus: StockCountOptionContainerStatus) {
        if containerStatus == .sealed {
            isNdcAdded = true
        } else {
            isDrugFound = true
        }
    }

    func reset() {
        isNdcAdded = false
        isDrugFound = false
    }

    // MARK: - HL7
    typealias HL7SimpleCallback = (Bool) -> Void

    // MARK: - Barcode Scan Flow

    func scannedPill(rawValueFromBarcodeOrQr: String, countType: CountType, image: UIImage? = nil) async {
        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let ndc = decoded.gtin ?? ""
        guard !ndc.isEmpty else { return }

        do {
            let drug = try await repo.resolveDrug(ndc: ndc, fallbackName: nil)
            drugName = drug.drug_name
            currentTransaction = await repo.createTransaction(
                drugId: drug.drug_id, countType: countType, barcodeImage: image,
                isFromPms: false, isControlled: nil, targetCount: nil,
                drugName: nil, batchId: nil, expirationDate: nil,
                lotNumber: nil, rxNo: nil, bucketId: nil
            )
            postTransactionUIUpdate(countType: countType)
        } catch {
            isDrugFound = false
        }
    }

    func scnnedPmsPill(rawValueFromBarcodeOrQr: String, countType: CountType, image: UIImage? = nil) {
        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let ndc = decoded.gtin ?? ""
        guard !ndc.isEmpty else { return }

        guard let existing = DrugMasterDAO.shared.fetchByNdc(ndc) else { return }

        drugName = existing.drug_name ?? ""

        Task(priority: .background) {
            await updaetTransaction(
                drugId: existing.drug_id,
                countType: countType,
                txnId: selectedTransaction?.txn_id ?? 0,
                barcodeImage: image
            )
        }

        refreshTransactionDetails()
        isDrugFound = true

        if countType == .FIXED {
            updateTargetCountForCurrentTransaction()
        }
    }

    // MARK: - Manual Entry

    func manualEntryDirectUpsert(ndc: String, drugName: String, countType: CountType) async {
        let trimmedNdc = ndc.trimmingCharacters(in: .whitespaces)
        let trimmedName = drugName.trimmingCharacters(in: .whitespaces)
        guard !trimmedNdc.isEmpty else { return }

        let drug: DrugMasterEntity
        if let existing = DrugMasterDAO.shared.fetchByNdc(trimmedNdc) {
            drug = existing
        } else {
            drug = repo.saveManualDrug(ndc: trimmedNdc, drugName: trimmedName)
        }

        self.drugName = drug.drug_name ?? trimmedName

        currentTransaction = await repo.createTransaction(
            drugId: drug.drug_id, countType: countType, barcodeImage: nil,
            isFromPms: false, isControlled: nil, targetCount: nil,
            drugName: nil, batchId: nil, expirationDate: nil,
            lotNumber: nil, rxNo: nil, bucketId: nil
        )

        if countType == .FIXED { updateTargetCountForCurrentTransaction() }
        refreshTransactionDetails()
        isDrugFound = true
        mannualDrugCreated = true
    }

    // MARK: - Transaction Helpers

    func updaetTransaction(
        drugId: Int64, countType: CountType, txnId: Int64,
        barcodeImage: UIImage? = nil, targetCount: Int32? = nil
    ) async {
        var savedPath = ""
        if let img = barcodeImage, let path = PhotoFileManager.shared.saveImage(img) {
            savedPath = path
        }
        repo.updateTransaction(
            txnId: txnId, drugId: drugId, countType: countType,
            targetCount: targetCount, barcodeImagePath: savedPath
        )
        if let user = UserDAO.shared.fetchByUserId(AppStorageManager.shared.userId ?? "") {
            currentTransaction = TransactionDAO.shared.fetchLatest(for: user)
        }
    }

    func addTransactionDetailToCurrentTransaction(
        pillCount: Int32, imagePath: String? = nil, type: String? = nil, isManual: Bool = false
    ) {
        guard let txnId = currentTransaction?.txn_id else { return }
        repo.addTransactionDetail(txnId: txnId, pillCount: pillCount, imagePath: imagePath, type: type, isManual: isManual)
        refreshTransactionDetails()
    }

    func addOrReplaceVialTransactionDetail(imagePath: String?) {
        guard let txnId = currentTransaction?.txn_id else { return }
        repo.addOrReplaceVialDetail(txnId: txnId, imagePath: imagePath)
    }

    func updateTargetCountForCurrentTransaction() {
        let joined = targetCount.joined()
        guard !joined.isEmpty, let value = Int32(joined),
              let txnId = currentTransaction?.txn_id else { return }
        repo.updateTargetCount(txnId: txnId, targetCount: value)
        currentTransaction = repo.fetchTransaction(txnId: txnId)
    }

    func updateNoteForCurrentTransaction(txn_id: Int64, note: String) {
        repo.updateNote(txnId: txn_id, note: note)
    }

    func softDeleteCurrentTransactionSelectedTransactionDetail(txnDetailId: Int64) {
        repo.softDeleteDetail(detailId: txnDetailId)
        refreshTransactionDetails()
    }

    func deleteAllDetailsOfCurrentTransaction() {
        guard let txnId = currentTransaction?.txn_id else { return }
        repo.softDeleteDetailsForStep(txnId: txnId, step: currentControlledStep)
        refreshTransactionDetails()
    }

    func refreshTransactionDetails() {
        guard let txnId = currentTransaction?.txn_id else { return }
        currentTransactionDetails = repo.getTransactionDetails(txnId: txnId, step: currentControlledStep)
    }

    func getCurrentTransaction(txnId: Int64) async {
        currentTransaction = repo.fetchTransaction(txnId: txnId)
        drugName = currentTransaction?.drug?.drug_name ?? "Unknown"
        refreshTransactionDetails()
    }

    func getTotalPillCountOfCurrentTransaction(details: [PillCountTransactionDetailsEntity]? = nil) -> Int {
        (details ?? currentTransactionDetails).reduce(0) { $0 + Int($1.pill_count) }
    }

    func getTotalPillCountOfCurrentTransactionByType(
        type: ControlledStep, details: [PillCountTransactionDetailsEntity]? = nil
    ) -> Int {
        (details ?? currentTransactionDetails)
            .filter { $0.type == type.rawValue }
            .reduce(0) { $0 + Int($1.pill_count) }
    }

    func getFixedCount() -> Int32? {
        guard let txn = selectedTransaction, txn.is_from_pms else { return nil }
        return txn.target_count
    }

    private func postTransactionUIUpdate(countType: CountType) {
        refreshTransactionDetails()
        if countType == .FIXED { updateTargetCountForCurrentTransaction() }
        isDrugFound = true
    }

    // MARK: - Controlled Drug

    var activeTransaction: PillCountTransactionEntity? {
        currentTransaction ?? selectedTransaction
    }

    func updateControlledTargetCount() {
        guard let txn = currentTransaction else { return }
        let txnId = txn.txn_id
        let target = Int(txn.target_count)

        switch currentControlledStep {
        case .scan, .containerInitiate:
            currentControlledTargetCount = 0
        case .targetVerification, .targetReverification, .vial:
            currentControlledTargetCount = target
        case .containerPending:
            let containerCount = repo.getTotalCountForStep(txnId: txnId, step: .containerInitiate)
            currentControlledTargetCount = max(Int(containerCount) - target, 0)
        }
    }

    func canCompleteStep(stepTotal: Int) -> Bool {
        guard let txn = currentTransaction else { return false }
        let target = Int(txn.target_count)

        switch currentControlledStep {
        case .containerInitiate:
            return stepTotal >= target
        case .targetVerification:
            return txn.count_type == CountType.FIXED.rawValue ? stepTotal == target : true
        case .targetReverification:
            return stepTotal == target
        case .containerPending:
            let containerCount = repo.getTotalCountForStep(txnId: txn.txn_id, step: .containerInitiate)
            return stepTotal == max(Int(containerCount) - target, 0)
        case .vial:
            return stepTotal == 0
        default:
            return false
        }
    }

    func isContainerPendingZero() -> Bool {
        guard let txn = currentTransaction else { return false }
        let containerCount = repo.getTotalCountForStep(txnId: txn.txn_id, step: .containerInitiate)
        let expected = Int(containerCount) - Int(txn.target_count)
        return currentControlledStep == .containerPending && expected == 0
    }

    func getTotalCountForCurrentStep() -> Int32 {
        guard let txnId = currentTransaction?.txn_id else { return 0 }
        return repo.getTotalCountForStep(txnId: txnId, step: currentControlledStep)
    }

    func getLastSavedControlledStep() -> ControlledStep? {
        guard let txn = selectedTransaction else { return nil }
        return repo.getLastCompletedStep(txnId: txn.txn_id)
    }

    func getControlledStep(pillCountTxn: PillCountTransactionEntity? = nil) {
        guard let txn = pillCountTxn else { return }
        guard let lastStep = repo.getLastCompletedStep(txnId: txn.txn_id) else {
            currentControlledStep = (txn.drug?.drug_type?.trimmingCharacters(in: .whitespaces).isEmpty == false)
                ? .containerInitiate
                : .targetVerification
            updateControlledTargetCount()
            return
        }
        currentControlledStep = lastStep
        updateControlledTargetCount()
    }

    func handleStepCompletion() {
        guard let txn = currentTransaction else { return }
        let steps = PillCountingStepResolver.getActiveSteps(txn: txn)
        guard let idx = steps.firstIndex(of: currentControlledStep) else { return }
        currentControlledStep = steps[idx + 1]
        updateControlledTargetCount()
    }

    func updateSubstitutedDrug(txnId: Int64, rawValue: String, countType: CountType, image: UIImage?) async {
        let decoded = decoder.decode(rawValue)
        let ndc = decoded.gtin ?? ""
        guard !ndc.isEmpty else { return }

        let drugId = generateUniqueDrugId()
        DrugMasterDAO.shared.fetchOrCreate(
            ndc: ndcComparisonResponse?.data?.scannedNdc?.packageNdc ?? "",
            drugId: drugId
        )
        DrugMasterDAO.shared.update(
            drugId: drugId,
            drugName: ndcComparisonResponse?.data?.scannedNdc?.lookupName,
            drugType: ndcComparisonResponse?.data?.scannedNdc?.deaSchedule
        )

        var savedPath = ""
        if let img = image, let path = PhotoFileManager.shared.saveImage(img) {
            savedPath = path
        }

        repo.updateSubstitutedDrug(txnId: txnId, drugId: drugId, countType: countType, barcodeImagePath: savedPath)
        isDrugFound = true
    }

    // MARK: - NDC Equivalence

    func checkIsNdcMatch(rawValueFromBarcodeOrQr: String) -> Bool {
        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let scannedNdc = decoded.gtin ?? ""
        guard let expectedNdc = getExpectedPmsNdc() else { return true }
        getControlledDrugInfo(targetNdc: expectedNdc, scannedNdc: scannedNdc)
        return false
    }

    func manualEnterdControlledDrug(scannedNdc: String) {
        let expectedNdc = getExpectedPmsNdc() ?? ""
        getControlledDrugInfo(targetNdc: expectedNdc, scannedNdc: scannedNdc)
    }

    func getControlledDrugInfo(targetNdc: String, scannedNdc: String) {
        isCheckingNdc = true
        Task {
            do {
                let response = try await repo.checkNdcEquivalence(targetNdc: targetNdc, scannedNdc: scannedNdc)
                ndcComparisonResponse = response
                let isEquivalent = response.data?.isNdcEquivalent ?? false
                let isSame = response.data?.isNdcSame ?? false
                isNdcEquivalent = isEquivalent
                scannedRxData = ParsedScanData(
                    ndcNo: response.data?.scannedNdc?.packageNdc,
                    drugName: response.data?.scannedNdc?.lookupName
                )
                if isEquivalent && !isSame {
                    showNdcEquivalencePopup = true
                } else if !isEquivalent && isSame {
                    showScannedDrugInfoPopoup = true
                } else {
                    showNdcEquivalencePopup = true
                    isNdcEquivalent = false
                }
            } catch {
                showNdcEquivalencePopup = true
                isNdcEquivalent = false
            }
            isCheckingNdc = false
        }
    }

    func markNdcVerified() {
        if let txnId = selectedTransaction?.txn_id {
            repo.updateNdcVerified(txnId: txnId, verified: true)
        }
    }

    func getExpectedPmsNdc() -> String? {
        guard let txn = selectedTransaction,
              let ndc = txn.drug?.ndc,
              !ndc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              txn.count_type == CountType.FIXED.rawValue else { return nil }
        return ndc
    }

    // MARK: - RX Flow

    func parseScanData(actualValue: String) {
        let barcodeFormat = AppStorageManager.shared.barcodeFormat
        do {
            let regex = try NSRegularExpression(pattern: "\\{(.*?)\\}")
            let matches = regex.matches(in: barcodeFormat, range: NSRange(barcodeFormat.startIndex..., in: barcodeFormat))
            let keys: [String] = matches.compactMap { match in
                if let range = Range(match.range(at: 1), in: barcodeFormat) {
                    return String(barcodeFormat[range]).trimmingCharacters(in: .whitespaces).uppercased()
                }
                return nil
            }
            let values = actualValue.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !keys.isEmpty, !values.isEmpty else {
                scannedRxData = ParsedScanData(); showRxFlowPopup = false; return
            }
            var mappedData: [String: String] = [:]
            for (index, key) in keys.enumerated() {
                if index < values.count { mappedData[key] = values[index] }
            }
            let ndc = mappedData["NDCNO"] ?? ""
            let bucket = mappedData["BUCKET"]?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? mappedData["BUCKET"]! : "NORMAL"
            self.selectedBucket = bucket

            Task {
                let resolvedDrugName = await repo.resolveDrugName(for: ndc)
                scannedRxData = ParsedScanData(
                    rxNo: mappedData["RXNO"],
                    ndcNo: ndc.isEmpty ? nil : ndc,
                    drugName: resolvedDrugName,
                    qty: mappedData["QTY"],
                    rawMap: mappedData
                )
                showRxFlowPopup = true
            }
        } catch {
            scannedRxData = ParsedScanData()
            showRxFlowPopup = false
        }
    }

    func createTransactionFromRxScan(countType: CountType = .FIXED) async {
        guard let rxData = scannedRxData else { return }

        let ndc = rxData.ndcNo ?? ""
        let name = rxData.drugName ?? ""
        let rxNo = rxData.rxNo
        let targetQty = Int32(rxData.qty ?? "") ?? 0

        let drug = repo.saveManualDrug(ndc: ndc, drugName: name)
        self.drugName = drug.drug_name ?? name

        currentTransaction = await repo.createTransaction(
            drugId: drug.drug_id, countType: countType, barcodeImage: nil,
            isFromPms: false, isControlled: nil,
            targetCount: targetQty > 0 ? targetQty : nil,
            drugName: name, batchId: nil, expirationDate: nil,
            lotNumber: nil, rxNo: rxNo, bucketId: selectedBucket
        )

        selectedTransaction = currentTransaction

        if targetQty > 0 {
            let digits = String(targetQty).map { String($0) }
            targetCount = Array(repeating: "", count: max(0, 4 - digits.count)) + digits
            updateTargetCountForCurrentTransaction()
        }

        showRxFlowPopup = false
        selectedBucket = ""
    }

    func matchesBarcodeFormat(_ value: String) -> Bool {
        let format = AppStorageManager.shared.barcodeFormat
        guard !format.isEmpty else { return false }
        do {
            let placeholderRegex = try NSRegularExpression(pattern: "\\{[^}]+\\}")
            let matches = placeholderRegex.matches(in: format, range: NSRange(format.startIndex..., in: format))
            guard !matches.isEmpty else { return false }
            var regexParts: [String] = []
            var lastEnd = format.startIndex
            for (i, match) in matches.enumerated() {
                guard let matchRange = Range(match.range, in: format) else { continue }
                let literal = String(format[lastEnd..<matchRange.lowerBound])
                let keyName = String(format[matchRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "{}")).uppercased()
                let isOptional = i == matches.count - 1 && keyName == "BUCKET"
                if isOptional {
                    regexParts.append("(?:\(NSRegularExpression.escapedPattern(for: literal))(.+?))?")
                } else {
                    if !literal.isEmpty { regexParts.append(NSRegularExpression.escapedPattern(for: literal)) }
                    regexParts.append("(.+?)")
                }
                lastEnd = matchRange.upperBound
            }
            let trailing = String(format[lastEnd...])
            if !trailing.isEmpty { regexParts.append(NSRegularExpression.escapedPattern(for: trailing)) }
            let pattern = "^" + regexParts.joined() + "$"
            let valueRegex = try NSRegularExpression(pattern: pattern)
            return valueRegex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        } catch {
            return false
        }
    }

    // MARK: - HL7

    func handleReceivedMessage(message: CompleteHL7Message, callback: HL7SimpleCallback? = nil) {
        guard let inboundType = classifyInboundMessage(message) else { return }
        buildNotification(message: message, messageType: inboundType)
        Task(priority: .background) {
            switch inboundType {
            case .FIXED:
                await createFixedHl7Transaction(message: message, inboundType: .FIXED, callback: callback)
            case .REGULAR:
                await createRegularHl7Transaction(message: message, inboundType: .REGULAR, callback: callback)
            default:
                callback?(false)
            }
        }
    }

    @MainActor
    private func createFixedHl7Transaction(
        message: CompleteHL7Message, inboundType: CountType, callback: HL7SimpleCallback? = nil
    ) async {
        guard let order = message.order, !message.medications.isEmpty else {
            callback?(false); return
        }
        var hasError = false
        for medication in message.medications {
            let ndc = medication.drugCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetCount = Int32(medication.requestedQty ?? "0") ?? 0
            guard !ndc.isEmpty else { hasError = true; continue }
            do {
                currentTransaction = try await HL7RepositoryImpl().resolveAndCreateTransaction(
                    ndc: ndc, drugName: medication.drugName, countType: inboundType,
                    targetCount: targetCount, rxNo: order.placerOrderId
                )
            } catch {
                Log("HL7 FIXED error for NDC \(ndc): \(error)")
                hasError = true
            }
        }
        callback?(!hasError)
    }

    @MainActor
    private func createRegularHl7Transaction(
        message: CompleteHL7Message, inboundType: CountType, callback: HL7SimpleCallback? = nil
    ) async {
        do {
            try await HL7RepositoryImpl().createBatchTransactions(
                medications: message.medications,
                requestId: message.header.messageControlId,
                bucketId: ""
            )
            callback?(true)
        } catch {
            Log("HL7 REGULAR error: \(error)")
            callback?(false)
        }
    }

    private func classifyInboundMessage(_ message: CompleteHL7Message) -> CountType? {
        if message.messageType == "RDE", message.triggerEvent == "O11", !message.medications.isEmpty { return .FIXED }
        if message.messageType == "INR", message.triggerEvent == "U04", !message.medications.isEmpty { return .REGULAR }
        return nil
    }

    func buildNotification(message: CompleteHL7Message, messageType: CountType) {
        let orderId = message.order?.placerOrderId ?? ""
        let meds = message.medications
        let title: String
        let body: String
        if messageType == .FIXED {
            title = "New RX Fill Request"
            body = meds.count == 1
                ? "Rx \(orderId) • \(meds[0].drugName) • Qty: \(Int(meds[0].requestedQty ?? "0") ?? 0)"
                : "Rx \(orderId) • \(meds.count) items to fill"
        } else {
            title = "Inventory Request"
            body = "\(meds.count) item\(meds.count == 1 ? "" : "s") need stock count"
        }
        HL7NotificationManager.show(title: title, body: body)
    }

    // MARK: - Toast

    func showToastMessage(text: String) {
        toastMessage = text
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showToast = false
        }
    }

    // MARK: - Reset

    func resetScanningState() {
        isDrugFound = nil
        drugName = nil
        currentTransaction = nil
        currentTransactionDetails = []
        ndcNumber = ""
        targetCount = Array(repeating: "", count: 4)
        isCheckingNdc = false
    }

    func resetState() {
        drugName = nil
        drugNameMannuallyEntered = ""
        isDrugFound = nil
        mannualDrugCreated = nil
        targetCount = Array(repeating: "", count: 4)
        note = ""
        currentTransaction = nil
        currentTransactionDetails = []
        selectedTransaction = nil
        showNdcEquivalencePopup = false
        isCheckingNdc = false
        isNdcEquivalent = false
        ndcComparisonResponse = nil
    }

    // MARK: - Private

    func autofillDrugNameIfAvailable(for ndc: String) {
        guard ndc.count >= 20 else { return }
        if let drug = DrugMasterDAO.shared.fetchByNdc(ndc),
           let name = drug.drug_name, !name.isEmpty, drugNameMannuallyEntered.isEmpty {
            drugNameMannuallyEntered = name
        }
    }

    func log(_ message: String) {
        print("🧪 [ManualPillFlow] \(message)")
    }

    private func generateUniqueDrugId() -> Int64 {
        let key = AppStorageManager.AppStorageKeys.drugIdCounter
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
