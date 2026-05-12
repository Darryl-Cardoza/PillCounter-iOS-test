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
    ){
        guard let inboundType = classifyInboundMessage(message) else {
            return
        }
        
        // Notify user about incoming order
  
        buildNotification(message: message, messageType: inboundType)

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
        var hasError = false


        guard let order = message.order else {
            callback?(false)
            return
        }


        guard !message.medications.isEmpty else {
            callback?(false)
            return
        }

        for medication in message.medications {

            // RXE-2.1
            let ndc = medication.drugCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let qty = Int(medication.requestedQty ?? "")

            // RXE-2.2
            let drugName = medication.drugName

            // RXE-3
            let targetCount = Int32(medication.requestedQty ?? "0") ?? 0

            let orderId = order.placerOrderId
            
            if ndc.isEmpty ||   qty == nil {
                hasError = true
                break
            }
            
            await processHl7DrugAndCreateTransaction(
                ndc: ndc,
                drugName: drugName,
                countType: inboundType,
                targetCount: targetCount,
                rxNo: orderId
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

    
    private func classifyInboundMessage(
        _ message: CompleteHL7Message
    ) -> CountType? {
        if message.messageType == "RDE",
           message.triggerEvent == "O11",
           !message.medications.isEmpty {
            return .FIXED
        }

        if message.messageType == "INR",
           message.triggerEvent == "U04",
           !message.medications.isEmpty {
            return .REGULAR
        }
        return nil
    }

    
    @MainActor
    func processHl7DrugAndCreateTransaction(
        ndc: String,
        drugName: String,
        countType: CountType,
        targetCount: Int32? = nil,
        rxNo: String? = nil
    ) async {

        guard !ndc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log("HL7: Missing NDC")
            return
        }

        var drugIdToUse: Int64 = 0
        var resolvedName: String = drugName

        if let existing = pillDataLocalStorage.getPillByNdc(by: ndc),
           let localName = existing.drug_name,
           !localName.isEmpty {

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

                    // Save to local DB
                    pillDataLocalStorage.saveManualPill(
                        ndc: response.data?.scannedNdc?.packageNdc ?? ndc,
                        drugId: newId,
                        drugName: lookup,
                        drugType: response.data?.scannedNdc?.deaSchedule,
                        packageQty: response.data?.scannedNdc?.safeQuantity ?? 0
                    )

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

        // MARK: 3️⃣ Create Transaction
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            isComingFromPms: true,
            isControlled: true,
            targetCount: targetCount,
            drugName: resolvedName,
            rxNo: rxNo
        )

        // MARK: 4️⃣ Refresh UI / State
        getAllTransactionDetailsOfTheCurrentTransaction()

        if countType == .FIXED {
            updateTargetCountForCurrentTransaction()
        }
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
