//
//  PillScanViewModel+HL7.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/03/26.
//
import Hl7Core


extension PillScanViewModel {
    
    func handleReceivedMessage(
        message: HL7Message,
        rawHl7: String = "",
        callback: HL7SimpleCallback? = nil
    ) {
        guard let msgType = classifyInboundMessage(message) else {
            print("Unknown HL7 message")
            return
        }

        print("MSG Type \(msgType)")

        Task(priority: .background) {
            switch msgType {
            case .dispenseOrder:
                await createFixedHl7Transaction(
                    message: message,
                    rawHl7: rawHl7,
                    inboundType: true,
                    callback: callback
                )
            case .editDispenseOrder:
                await editFixedHl7Transaction(
                    message: message,
                    rawHl7: rawHl7,
                    inboundType: true,
                    callback: callback
                )
            case .inventoryRequest:
                await createRegularHl7Transaction(
                    message: message,
                    inboundType: false,
                    callback: callback
                )
            case .cancelOrder:
                await cancelOrderTransactions(
                    message: message,
                    callback: callback
                )
            case .zuiOrderPacket:
                await handleZuiOrderPacketDispenseRequest(
                    message: message,
                    callback: callback
                )
            case .zniDispenseResult:
                await handleZniDispenseResult(
                    message: message,
                    callback: callback
                )
            }
        }
    }
    
    func classifyInboundMessage(
        _ message: HL7Message
    ) -> MessageType? {

        // Cancel Order — ORC|CA
        if message.order?.orderControl == "CA",
           !(message.order?.placerOrderNumber.isNullOrBlank ?? true) {
            return .cancelOrder
        }

        // Edit Dispense Request — ORC|XO
        if message.messageType == "RDE",
           message.triggerEvent == "O11",
           message.order?.orderControl == "XO",
           !(message.order?.placerOrderNumber.isNullOrBlank ?? true),
           !message.medications.isEmpty {
            return .editDispenseOrder
        }

        // New Dispense Request — ORC|NW (or any other control)
        if message.messageType == "RDE",
           message.triggerEvent == "O11",
           !message.medications.isEmpty {
            return .dispenseOrder
        }

        // Vivid ZUI order-data-packet — RDE^O01 or O11, PMSS -> Vivid, no RXE/ORC present.
        if message.messageType == "RDE",
           message.order == nil,
           message.medications.isEmpty,
           message.zuiOrder != nil {
            return .zuiOrderPacket
        }

        // Eyecon ZNI dispense-result packet — RDE^O01 (or O11), no RXE/ORC present.
        if message.messageType == "RDE",
           message.order == nil,
           message.medications.isEmpty,
           message.zniSegment != nil {
            return .zniDispenseResult
        }

        // Inventory Request
        if message.messageType == "INR",
           message.triggerEvent == "U04",
           !message.medications.isEmpty {
            return .inventoryRequest
        }

        return nil
    }
    

    
    @MainActor
    private func createFixedHl7Transaction(
        message: HL7Message,
        rawHl7: String = "",
        inboundType: Bool,
        callback: HL7SimpleCallback? = nil
    ) async {
        var hasError = false


        guard let order = message.order else {
            callback?(false)
            return
        }


        guard !message.medications.isEmpty else {
            callback?(false)
            return
        }

        // ZPR-2 priority, e.g. "STAT"/"URGENT"/"ROUTINE"/"TIMED".
        let priority: String? = {
            let value = message.priority?.priority
            return (value?.isEmpty ?? true) ? nil : value
        }()

        let dispenseAmounts = Self.extractRxeDispenseAmounts(from: rawHl7)

        for (index, medication) in message.medications.enumerated() {

            // RXE-2.1
            let ndc = medication.giveCode.trimmingCharacters(in: .whitespacesAndNewlines)

            // RXE-3 — dispenseAmount is read from raw text; see extractRxeDispenseAmounts.
            let dispenseAmount = dispenseAmounts[safe: index] ?? medication.dispenseAmount
            let qty = Int(dispenseAmount)

            // RXE-2.2
            let drugName = medication.giveName

            let targetCount = Int32(dispenseAmount) ?? 0

            let orderId = order.placerOrderNumber

            if ndc.isEmpty || qty == nil {
                hasError = true
                break
            }

            // ZIN|<setId>|EXPECTED_ON_HAND|<qty>|| — setId is 1-based medication index
            let medicationSetId = String(index + 1)
            let inventoryCount: Int32? = message.zinSegments
                .first(where: { $0.setId == medicationSetId && $0.dispenseType == "EXPECTED_ON_HAND" })
                .flatMap { Int32($0.quantity) }

            await processHl7DrugAndCreateTransaction(
                ndc: ndc,
                drugName: drugName,
                isDispense: inboundType,
                targetCount: targetCount,
                rxNo: orderId,
                priority: priority,
                inventoryCount: inventoryCount,
                messageControlId: message.messageControlId
            )
        }

        callback?(!hasError)
    }
    

    @MainActor
    private func createRegularHl7Transaction(
        message: HL7Message,
        inboundType: Bool,
        callback: HL7SimpleCallback? = nil
    ) async {
        await createBatchAndTxnsFromHL7Request(
            medications: message.medications,
            requestId: message.messageControlId,
            bucketId: ""
        )

        let medCount = message.medications.count
        HL7NotificationManager.show(
            title: L10n.Hl7Notification.inventoryRequestTitle,
            body: medCount == 1
                ? L10n.Hl7Notification.inventoryRequestBodySingle
                : L10n.Hl7Notification.inventoryRequestBodyMultiple(medCount)
        )

        callback?(true)
    }

    @MainActor
    private func editFixedHl7Transaction(
        message: HL7Message,
        rawHl7: String = "",
        inboundType: Bool,
        callback: HL7SimpleCallback? = nil
    ) async {
        guard let rxNo = message.order?.placerOrderNumber, !rxNo.isEmpty else {
            callback?(false)
            return
        }
        guard let medication = message.medications.first else {
            callback?(false)
            return
        }

        // 1. Find active transaction; restore soft-deleted one if needed
        let currentUser = userDataLocalStorage.fetchByUserId(userId)
        var existingTxn = currentUser.flatMap { transactionDAO.fetchByRxNo(rxNo, for: $0).first }
        if existingTxn == nil {
            if let currentUser, let deleted = transactionDAO.fetchDeletedByRxNo(rxNo, for: currentUser) {
                Log("HL7 ORC|XO: restoring deleted txnId=\(deleted.txn_id) for rxNo=\(rxNo)")
                transactionDAO.restoreDeleted(txnId: deleted.txn_id)
                existingTxn = transactionDAO.fetchById(deleted.txn_id)
            }
        }

        guard let txn = existingTxn else {
            // Silently ignore status-only updates (HD/CM/CA) for orders not on this device.
            // Only notify if it was a genuine drug/qty edit (XO with no prior txn).
            let orderStatusRaw: String? = {
                let status = message.order?.orderStatus.uppercased()
                return (status?.isEmpty ?? true) ? nil : status
            }()
            let isStatusOnlyUpdate = (orderStatusRaw == "HD" || orderStatusRaw == "CM" || orderStatusRaw == "CA")
            if !isStatusOnlyUpdate {
                HL7NotificationManager.show(
                    title: "Edit Rx Failed",
                    body: "No transaction found for Rx \(rxNo)"
                )
            }
            Log("HL7 ORC|XO: no active or restorable transaction for rxNo=\(rxNo), orderStatus=\(orderStatusRaw ?? "nil") — ignoring")
            callback?(false)
            return
        }

        // 2. Resolve drug: local DB first, then API fallback
        let hl7Ndc = medication.giveCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let hl7DrugName = medication.giveName
        // RXE-3 — dispenseAmount is read from raw text; see extractRxeDispenseAmounts.
        let dispenseAmount = Self.extractRxeDispenseAmounts(from: rawHl7).first ?? medication.dispenseAmount
        let newTargetCount = Int32(dispenseAmount) ?? 0

        var resolvedDrugId: Int64 = txn.drug_id
        var resolvedDrugName: String = hl7DrugName

        if let local = drugMasterDAO.fetchByNdc(hl7Ndc),
           let localName = local.drug_name, !localName.isEmpty {
            resolvedDrugId = local.drug_id
            resolvedDrugName = localName
            Log("HL7 ORC|XO: drug found locally → \(resolvedDrugName)")
        } else {
            let request = NdcValidationRequest(targetNdc: hl7Ndc, scannedNdc: hl7Ndc)
            do {
                let response = try await controlledRepo.getControlledDrugInfo(
                    ndcValidationRequest: request
                )
                if let scannedNdc = response.data?.scannedNdc,
                   let lookup = scannedNdc.lookupName, !lookup.isEmpty {
                    let newId = generateUniqueDrugId()
                    drugMasterDAO.upsertFromApi(
                        ndc:    hl7Ndc,
                        drugId: newId,
                        drug:   scannedNdc
                    )
                    resolvedDrugId = newId
                    resolvedDrugName = lookup
                    Log("HL7 ORC|XO: drug created via API → \(lookup)")
                } else {
                    Log("HL7 ORC|XO: API returned no drug name for NDC=\(hl7Ndc) — aborting edit")
                    HL7NotificationManager.show(
                        title: "Edit Rx Failed",
                        body: "Drug not found for Rx \(rxNo), NDC \(hl7Ndc)"
                    )
                    callback?(false)
                    return
                }
            } catch {
                Log("HL7 ORC|XO: API failed for NDC=\(hl7Ndc) → \(error.localizedDescription)")
                HL7NotificationManager.show(
                    title: "Edit Rx Failed",
                    body: "Drug not found for Rx \(rxNo), NDC \(hl7Ndc)"
                )
                callback?(false)
                return
            }
        }

        // 3. ZPR-2 priority
        let newPriority: String? = {
            let value = message.priority?.priority
            return (value?.isEmpty ?? true) ? nil : value
        }()

        // 4. Apply all updates atomically; resets is_synced so the result is re-sent to PMS
        let txnId = txn.txn_id
        transactionDAO.updateFromHL7Edit(
            txnId: txnId,
            drugId: resolvedDrugId,
            targetCount: newTargetCount,
            priority: newPriority,
            refillNo: nil
        )

        Log("HL7 ORC|XO applied: txnId=\(txnId), rxNo=\(rxNo), drugId=\(resolvedDrugId), targetCount=\(newTargetCount), priority=\(newPriority ?? "nil")")

        // 5. Map and apply order status
        let orderStatusRaw: String? = {
            let status = message.order?.orderStatus.uppercased()
            return (status?.isEmpty ?? true) ? nil : status
        }()
        let newStatus = Self.mapHl7OrderStatus(orderStatusRaw)
        if let newStatus {
            transactionDAO.updateStatus(txnId: txnId, status: newStatus)
        }

        // 6. If CA — soft-delete after the update
        if orderStatusRaw == "CA" {
            Log("HL7 ORC|XO status=CA — soft-deleting txnId=\(txnId) after update")
            transactionDAO.softDelete(txnId: txnId)
            HL7NotificationManager.show(
                title: L10n.Hl7Notification.rxCancelledTitle,
                body: "Rx \(rxNo) • \(resolvedDrugName)"
            )
            callback?(true)
            return
        }

        // 7. If ON_HOLD
        if newStatus == .ON_HOLD {
            Log("HL7 ORC|XO status=HD — transaction placed on hold txnId=\(txnId)")
            getAllTransactionDetailsOfTheCurrentTransaction()
            HL7NotificationManager.show(
                title: L10n.Hl7Notification.rxOnHoldTitle,
                body: "Rx \(rxNo) • \(resolvedDrugName)"
            )
            callback?(true)
            return
        }

        // 8. If COMPLETED — updateStatus already fired transactionsDidChange which auto-enqueues PMS sync
        if newStatus == .COMPLETED {
            Log("HL7 ORC|XO status=CM — transaction marked completed, PMS sync enqueued via transactionsDidChange")
            HL7NotificationManager.show(
                title: L10n.Hl7Notification.rxCompletedTitle,
                body: "Rx \(rxNo) • \(resolvedDrugName)"
            )
            callback?(true)
            return
        }

        // 9. Refresh UI
        getAllTransactionDetailsOfTheCurrentTransaction()
        updateTargetCountForCurrentTransaction()

        HL7NotificationManager.show(
            title: L10n.Hl7Notification.rxUpdatedTitle,
            body: "Rx \(rxNo) • \(resolvedDrugName) • \(L10n.Hl7Notification.qtyLabel): \(newTargetCount)"
        )

        callback?(true)
    }

    // Maps HL7 ORC-5 order status to CountStatus.
    // CA is handled separately via soft-delete; returns nil here.
    static func mapHl7OrderStatus(_ orderStatus: String?) -> CountStatus? {
        switch orderStatus?.uppercased() {
        case "IP": return .PARTIAL
        case "CM": return .COMPLETED
        case "HD": return .ON_HOLD
        default:   return nil
        }
    }

    @MainActor
    func processHl7DrugAndCreateTransaction(
        ndc: String,
        drugName: String,
        isDispense: Bool,
        targetCount: Int32? = nil,
        rxNo: String? = nil,
        priority: String? = nil,
        inventoryCount: Int32? = nil,
        messageControlId: String? = nil,
        transactionOrderId: String? = nil
    ) async {

        var drugType: String? = nil

        guard !ndc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log("HL7: Missing NDC")
            return
        }

        var drugIdToUse: Int64 = 0
        var resolvedName: String = drugName

        if let existing = drugMasterDAO.fetchByNdc(ndc),
           let localName = existing.drug_name,
           !localName.isEmpty {

            drugType = existing.drug_type
            drugIdToUse = existing.drug_id
            resolvedName = localName

            Log("HL7: Drug found locally → \(resolvedName)")
        }
        else {

            let request = NdcValidationRequest(
                targetNdc: ndc,
                scannedNdc: ndc
            )

            do {
                let response = try await controlledRepo.getControlledDrugInfo(
                    ndcValidationRequest: request
                )

                if let scannedNdc = response.data?.scannedNdc,
                   let lookup = scannedNdc.lookupName,
                   !lookup.isEmpty {

                    let newId = generateUniqueDrugId()

                    drugIdToUse = newId
                    resolvedName = lookup

                    // Use the original HL7 ndc as the key so subsequent getPillByNdc
                    // lookups (which also use the HL7 ndc) find this record.
                    // packageNdc from the API may differ, which would orphan the saved
                    // drug and break the transaction's drug relationship.
                    drugMasterDAO.upsertFromApi(
                        ndc:    ndc,
                        drugId: newId,
                        drug:   scannedNdc
                    )

                    drugType = scannedNdc.scheduleType

                    Log("HL7: Drug created via API → \(lookup)")
                } else {
                    Log("HL7: API returned empty drug name")
                    return
                }

            } catch {
                Log("HL7: API failed for NDC \(ndc) → \(error.localizedDescription)")
                return
            }
        }

        let isControlled = !(drugType?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        let hasInventory = (inventoryCount ?? 0) > 0

        let initialWorkFlowStep: String = isControlled
            ? ControlledStep.containerInitiate.rawValue
            : ControlledStep.targetVerification.rawValue

        // MARK: 3 Create or update transaction (dedup by rxNo)
        let currentUser = userDataLocalStorage.fetchByUserId(userId)
        var isNewTxn = true

        if let rxNo, !rxNo.isEmpty, let user = currentUser,
           let existing = transactionDAO.fetchByRxNo(rxNo, for: user).first {
            // Already exists — update in place, do NOT create a duplicate
            isNewTxn = false
            transactionDAO.updateFromHL7Edit(
                txnId: existing.txn_id,
                drugId: drugIdToUse,
                targetCount: targetCount ?? existing.target_count,
                priority: priority ?? existing.txn_priority,
                refillNo: nil
            )
            TransactionStore.shared.setHl7Identifiers(
                txnId: existing.txn_id,
                messageControlId: messageControlId,
                transactionOrderId: transactionOrderId
            )
            self.currentTransaction = transactionDAO.fetchById(existing.txn_id)
            Log("HL7: Rx \(rxNo) already exists (txnId=\(existing.txn_id)) — updated in place, no new txn created")
        } else {
            await createTransaction(
                drugId: drugIdToUse,
                isDispense: isDispense,
                isComingFromPms: true,
                isControlled: true,
                targetCount: targetCount,
                drugName: resolvedName,
                rxNo: rxNo,
                priority: priority,
                workFlowStep: initialWorkFlowStep
            )

            if let txnId = currentTransaction?.txn_id {
                TransactionStore.shared.setHl7Identifiers(
                    txnId: txnId,
                    messageControlId: messageControlId,
                    transactionOrderId: transactionOrderId
                )
            }

            if isControlled, hasInventory, let invCount = inventoryCount,
               let txnId = currentTransaction?.txn_id {

                transactionDetailDAO.add(
                    txnId: txnId,
                    pillCount: invCount,
                    imagePath: nil,
                    type: ControlledStep.containerInitiate.rawValue,
                    isManual: true
                )

                transactionDAO.updateWorkflowStep(txnId: txnId, step: .targetVerification)
                Log("HL7: Pre-filled CONTAINER_INITIATE with \(invCount) from PMS; advanced to targetVerification")
            }
        }

        // MARK: 4 Refresh UI / State
        getAllTransactionDetailsOfTheCurrentTransaction()

        if isDispense {
            updateTargetCountForCurrentTransaction()
        }

        // MARK: 5 Notify after successful insert/update
        let rxLabel = rxNo ?? ""
        if isNewTxn {
            HL7NotificationManager.show(
                title: L10n.Hl7Notification.newRxTitle,
                body: rxLabel.isEmpty
                    ? "\(resolvedName) • \(L10n.Hl7Notification.qtyLabel): \(targetCount ?? 0)"
                    : "Rx \(rxLabel) • \(resolvedName) • \(L10n.Hl7Notification.qtyLabel): \(targetCount ?? 0)"
            )
        } else {
            HL7NotificationManager.show(
                title: L10n.Hl7Notification.rxUpdatedTitle,
                body: rxLabel.isEmpty
                    ? "\(resolvedName) • \(L10n.Hl7Notification.qtyLabel): \(targetCount ?? 0)"
                    : "Rx \(rxLabel) • \(resolvedName) • \(L10n.Hl7Notification.qtyLabel): \(targetCount ?? 0)"
            )
        }
    }
    
    
    /// Vivid order-data-packet dispense request: RDE^O11 carrying only a ZUI
    /// segment (no RXE/ORC) — parse the drug/quantity/Rx info directly from ZUI.
    /// Warn and ignore if the NDC is missing.
    @MainActor
    private func handleZuiOrderPacketDispenseRequest(
        message: HL7Message,
        callback: HL7SimpleCallback? = nil
    ) async {
        guard let zui = message.zuiOrder else {
            callback?(false)
            return
        }

        let ndc = zui.ndc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ndc.isEmpty else {
            Log("HL7 ZUI order packet: missing NDC — ignoring")
            callback?(false)
            return
        }

        let targetCount = Int32(zui.orderDispenseQuantity) ?? 0
        let rxNo = zui.orderRxNumber.isEmpty ? nil : zui.orderRxNumber

        await processHl7DrugAndCreateTransaction(
            ndc: ndc,
            drugName: zui.orderDrugName,
            isDispense: true,
            targetCount: targetCount,
            rxNo: rxNo,
            messageControlId: message.messageControlId,
            transactionOrderId: zui.orderTransactionOrderId.isEmpty ? nil : zui.orderTransactionOrderId
        )

        callback?(true)
    }

    /// Eyecon dispense-result packet: RDE^O01 (or O11) carrying only a ZNI
    /// segment (no RXE/ORC) — parse the drug/quantity/Rx info directly from ZNI.
    /// Warn and ignore if the NDC is missing.
    @MainActor
    private func handleZniDispenseResult(
        message: HL7Message,
        callback: HL7SimpleCallback? = nil
    ) async {
        guard let zni = message.zniSegment else {
            callback?(false)
            return
        }

        let ndc = zni.ndc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ndc.isEmpty else {
            Log("HL7 ZNI dispense result: missing NDC — ignoring")
            callback?(false)
            return
        }

        let targetCount = Int32(zni.dispenseAmount) ?? 0
        let rxNo = zni.prescriptionNumber.isEmpty ? nil : zni.prescriptionNumber

        await processHl7DrugAndCreateTransaction(
            ndc: ndc,
            drugName: zni.drugName,
            isDispense: true,
            targetCount: targetCount,
            rxNo: rxNo,
            messageControlId: message.messageControlId,
            transactionOrderId: zni.fillerOrderNumber.isEmpty ? nil : zni.fillerOrderNumber
        )

        callback?(true)
    }

    @MainActor
    private func cancelOrderTransactions(
        message: HL7Message,
        callback: HL7SimpleCallback? = nil
    ) async {
        guard let rxNo = message.order?.placerOrderNumber, !rxNo.isEmpty else {
            callback?(false)
            return
        }

        let currentUser = userDataLocalStorage.fetchByUserId(userId)
        let txns = currentUser.map { transactionDAO.fetchByRxNo(rxNo, for: $0) } ?? []
        guard !txns.isEmpty else {
            Log("HL7: Cancel order — no transactions found for Rx \(rxNo)")
            callback?(false)
            return
        }

        for txn in txns {
            transactionDAO.softDelete(txnId: txn.txn_id)
        }

        Log("HL7: Cancelled \(txns.count) transaction(s) for Rx \(rxNo)")
        getAllTransactionDetailsOfTheCurrentTransaction()

        HL7NotificationManager.show(
            title: L10n.Hl7Notification.rxCancelledTitle,
            body: "Rx \(rxNo)"
        )

        callback?(true)
    }


    // WORKAROUND: RXESegment.dispenseAmount currently returns "" instead of RXE-3
    // (confirmed against "RXE||<ndc>^<name>^NDC|<qty>|<units>" — library bug, fix
    // requested upstream). Until fixed, read RXE-3 directly from the raw HL7 text,
    // one value per RXE segment in appearance order (matches message.medications order).
    static func extractRxeDispenseAmounts(from raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet.newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("RXE|") else { return nil }
            let fields = trimmed.components(separatedBy: "|")
            return fields[safe: 3]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // Returns the raw priority string from ZPR segment, e.g. "High", "STAT".
    // Format: ZPR|<setId>|PRIORITY|<value>
    static func extractZprPriorityString(from raw: String) -> String? {
        for line in raw.components(separatedBy: CharacterSet.newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("ZPR|") else { continue }
            let fields = trimmed.components(separatedBy: "|")
            if fields.count >= 4,
               fields[safe: 2]?.uppercased() == "PRIORITY",
               let value = fields[safe: 3]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // buildNotification is replaced by per-action notifications fired after successful operation
//    func buildNotification(
//        message: CompleteHL7Message,
//        messageType: CountType
//    ) {
//        let orderId = message.order?.placerOrderId ?? ""
//        let meds = message.medications
//        let title: String
//        let body: String
//        if messageType == .FIXED {
//            title = "New RX Fill Request"
//            if meds.count == 1 {
//                let med = meds[0]
//                let name = med.drugName
//                let qty = Int(med.requestedQty ?? "0") ?? 0
//                body = "Rx \(orderId) • \(name) • Qty: \(qty)"
//            } else {
//                body = "Rx \(orderId) • \(meds.count) items to fill"
//            }
//        } else {
//            title = "Inventory Request"
//            if meds.count == 1 {
//                body = "\(meds.count) item need stock count"
//            } else {
//                body = "\(meds.count) items need stock count"
//            }
//        }
//        HL7NotificationManager.show(title: title, body: body)
//    }
}


enum MessageType {
    case dispenseOrder
    case editDispenseOrder
    case inventoryRequest
    case cancelOrder
    case zuiOrderPacket
    case zniDispenseResult
}

extension String {
    var isNullOrBlank: Bool {
        return self.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
