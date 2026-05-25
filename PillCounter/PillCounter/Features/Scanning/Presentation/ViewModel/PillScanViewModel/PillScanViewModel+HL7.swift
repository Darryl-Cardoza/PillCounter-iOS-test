//
//  PillScanViewModel+HL7.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/03/26.
//
import ComposeApp


extension PillScanViewModel {
    
    func handleReceivedMessage(
        message: CompleteHL7Message,
        callback: HL7SimpleCallback? = nil
    ) {

        guard let msgType = classifyInboundMessage(message) else {
            print("Unknown HL7 message")
            return
        }

        let countType: CountType =
            (msgType == .dispenseOrder) ? .FIXED : .REGULAR

        if msgType == .dispenseOrder ||
            msgType == .inventoryRequest {

            buildNotification(
                message: message,
                messageType: countType
            )
        }

        print("MSG Type \(msgType)")

        Task(priority: .background) {

            if msgType == .dispenseOrder {

                await createFixedHl7Transaction(
                    message: message,
                    inboundType: .FIXED,
                    callback: callback
                )

            } else if msgType == .inventoryRequest {

                await createRegularHl7Transaction(
                    message: message,
                    inboundType: .REGULAR,
                    callback: callback
                )

            } else if msgType == .cancelOrder {

                await cancelOrderTransactions(
                    message: message,
                    callback: callback
                )
            }
        }
    }
    
    func classifyInboundMessage(
        _ message: CompleteHL7Message
    ) -> Hl7MessageType? {

        // Cancel Order
        if message.order?.orderControl == "CA",
           !(message.order?.placerOrderId.isEmpty ?? true) {
            return .cancelOrder
        }

        // Dispense Request
        if message.messageType == "RDE",
           message.triggerEvent == "O11",
           !message.medications.isEmpty {

            return .dispenseOrder
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
        message: CompleteHL7Message,
        inboundType: CountType,
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

        let priority = message.priority == .unknown ? nil : message.priority.name

        for (index, medication) in message.medications.enumerated() {

            // RXE-2.1
            let ndc = medication.drugCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let qty = Int(medication.requestedQty ?? "")

            // RXE-2.2
            let drugName = medication.drugName

            // RXE-3
            let targetCount = Int32(medication.requestedQty ?? "0") ?? 0

            let orderId = order.placerOrderId

            if ndc.isEmpty || qty == nil {
                hasError = true
                break
            }

            // ZIN|<setId>|EXPECTED_ON_HAND|<qty>|| — setId is 1-based medication index
            let medicationSetId = Int32(index + 1)
            let inventoryCount: Int32? = message.zinSegments
                .first(where: { $0.setId == medicationSetId && $0.dispenseType == "EXPECTED_ON_HAND" })
                .map { $0.quantity }

            await processHl7DrugAndCreateTransaction(
                ndc: ndc,
                drugName: drugName,
                countType: inboundType,
                targetCount: targetCount,
                rxNo: orderId,
                priority: priority,
                inventoryCount: inventoryCount
            )
        }

        callback?(!hasError)
    }
    

    @MainActor
    private func createRegularHl7Transaction(
        message: CompleteHL7Message,
        inboundType: CountType,
        callback: HL7SimpleCallback? = nil
    ) async {
        await createBatchAndTxnsFromHL7Request(
            medications: message.medications,
            requestId: message.header.messageControlId,
            bucketId: ""
        )
        
        callback?(true)
    }

    
//    private func classifyInboundMessage(
//        _ message: CompleteHL7Message
//    ) -> CountType? {
//        if message.messageType == "RDE",
//           message.triggerEvent == "O11",
//           !message.medications.isEmpty {
//            return .FIXED
//        }
//
//        if message.messageType == "INR",
//           message.triggerEvent == "U04",
//           !message.medications.isEmpty {
//            return .REGULAR
//        }
//        return nil
//    }

    
    @MainActor
    func processHl7DrugAndCreateTransaction(
        ndc: String,
        drugName: String,
        countType: CountType,
        targetCount: Int32? = nil,
        rxNo: String? = nil,
        priority: String? = nil,
        inventoryCount: Int32? = nil
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

                if let lookup = response.data?.scannedNdc?.lookupName,
                   !lookup.isEmpty {

                    let newId = generateUniqueDrugId()

                    drugIdToUse = newId
                    resolvedName = lookup

                    // Use the original HL7 ndc as the key so subsequent getPillByNdc
                    // lookups (which also use the HL7 ndc) find this record.
                    // packageNdc from the API may differ, which would orphan the saved
                    // drug and break the transaction's drug relationship.
                    drugMasterDAO.saveManual(
                        ndc: ndc,
                        drugId: newId,
                        drugName: lookup,
                        drugType: response.data?.scannedNdc?.deaSchedule,
                        packageQty: response.data?.scannedNdc?.safeQuantity ?? 0
                    )

                    drugType = response.data?.scannedNdc?.deaSchedule

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

        // MARK: 3 Create Transaction
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            isComingFromPms: true,
            isControlled: true,
            targetCount: targetCount,
            drugName: resolvedName,
            rxNo: rxNo,
            priority: priority,
            workFlowStep: initialWorkFlowStep
        )

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

        // MARK: 4 Refresh UI / State
        getAllTransactionDetailsOfTheCurrentTransaction()

        if countType == .FIXED {
            updateTargetCountForCurrentTransaction()
        }
    }
    
    
    @MainActor
    private func cancelOrderTransactions(
        message: CompleteHL7Message,
        callback: HL7SimpleCallback? = nil
    ) async {
        guard let rxNo = message.order?.placerOrderId, !rxNo.isEmpty else {
            callback?(false)
            return
        }

        let txns = transactionDAO.fetchByRxNo(rxNo)
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
        callback?(true)
    }


    func buildNotification(
        message: CompleteHL7Message,
        messageType: CountType
    ) {

        let orderId = message.order?.placerOrderId ?? ""
        let meds = message.medications

        let title: String
        let body: String

        if messageType == .FIXED {

            title = "New RX Fill Request"

            if meds.count == 1 {
                let med = meds[0]
                let name = med.drugName
                let qty = Int(med.requestedQty ?? "0") ?? 0

                body = "Rx \(orderId) • \(name) • Qty: \(qty)"
            } else {
                body = "Rx \(orderId) • \(meds.count) items to fill"
            }

        } else {
            title = "Inventory Request"

            if meds.count == 1 {
                body = "\(meds.count) item need stock count"
            } else {
                body = "\(meds.count) items need stock count"
            }
        }

        HL7NotificationManager.show(
            title: title,
            body: body
        )
    }
}
