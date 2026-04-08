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

            // RXE-2.2
            let drugName = medication.drugName

            // RXE-3
            let targetCount = Int32(medication.requestedQty ?? "0") ?? 0

            let orderId = order.placerOrderId
            
            await processHl7DrugAndCreateTransaction(
                ndc: ndc,
                drugName: drugName,
                countType: inboundType,
                targetCount: targetCount,
                rxNo: orderId
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
            print("Regular Count: No inventory found")
            callback?(false)
            return
        }

        // FIXED MAPPING (based on your HL7 format)
        let ndc = inventory.substanceStatusCode ?? ""
        let drugName = inventory.substanceStatusDescription ?? "Unknown Drug"
        let targetCount = Int32(inventory.substanceTypeCode ?? "") ?? 0

        print("Parsed INV → NDC: \(ndc), Name: \(drugName), Count: \(targetCount)")

        await processHl7DrugAndCreateTransaction(
            ndc: ndc,
            drugName: drugName,
            countType: inboundType,
            targetCount: targetCount,
            rxNo: message.order?.placerOrderId
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
           message.triggerEvent == "U05",
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
        targetCount: Int32? = nil,
        rxNo: String? = nil
    ) async {

        print("🧾 HL7 Drug Processing → NDC: \(ndc), Name: \(drugName)")

        var drugIdToUse: Int64

        // Create new drug synchronously
        drugIdToUse = generateUniqueDrugId()

        print("Drug not found — creating new DrugMaster entry")

        pillDataLocalStorage.saveManualPill(
            ndc: ndc,
            drugId: drugIdToUse,
            drugName: drugName,
        
        )

        self.drugName = drugName
    

        // 3️⃣ Create transaction
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            isComingFromPms: true,
            isControlled: true,
            targetCount: targetCount,
            drugName: drugName,
            rxNo: rxNo
        )

        // 4️⃣ Refresh transaction details
        getAllTransactionDetailsOfTheCurrentTransaction()

        // 5️⃣ Update target count if fixed
        if countType == .FIXED {
            updateTargetCountForCurrentTransaction()
        }
    }
    
}
