//
//  HL7CompletionBuilder.swift
//

import ComposeApp

// MARK: - CONFIG

struct HL7Config {
    let sendingApplication: String
    let sendingFacility: String
    let receivingApplication: String
    let receivingFacility: String
    let versionId: String
}

final class HL7ConfigProvider {
    
    static func getConfig(user: UserEntity?) -> HL7Config {
        return HL7Config(
            sendingApplication: Bundle.main.bundleIdentifier ?? "UNKNOWN_APP",
            sendingFacility: user?.pharmacy_name ?? "UNKNOWN_FACILITY",
            receivingApplication: "PMS",
            receivingFacility: user?.pharmacy_name ?? "UNKNOWN_FACILITY",
            versionId: "2.5"
        )
    }
}

// MARK: - BUILDER

final class HL7CompletionBuilder {
    
    func buildCompletionMessage(
        txn: PillCountTransactionEntity,
        user: UserEntity?
    ) -> String {
        
        let timestamp = currentHL7Timestamp()
        let messageId = UUID().uuidString
        let config = HL7ConfigProvider.getConfig(user: user)
        
        // MARK: Header
        let header = MessageHeaderData(
            fieldSeparator: "|",
            encodingCharacters: HL7Constants.shared.ENCODING_CHARACTERS,
            sendingApplication: config.sendingApplication,
            sendingFacility: config.sendingFacility,
            receivingApplication: config.receivingApplication,
            receivingFacility: config.receivingFacility,
            messageDateTime: timestamp,
            messageType: "RDS",
            triggerEvent: "O13",
            messageControlId: messageId,
            processingId: "P",
            versionId: config.versionId,
            countryCode: nil
        )
        
        // MARK: Drug
        guard let drug = txn.drug else {
            fatalError("Drug mapping missing for txn_id: \(txn.txn_id)")
        }
        
        let dispensedQty = calculateDispensed(from: txn)
        let requestedQty = Int(txn.target_count)
        
        // MARK: DISPENSE
        let dispense = DispenseData(
            dispenseSubId: nil,
            drugCode: drug.ndc ?? "",
            drugName: drug.drug_name ?? "",
            drugCodeSystem: "NDC",
            dateTimeDispensed: timestamp,
            quantityDispensed: "\(dispensedQty)",
            unitCode: resolveUnitCode(from: txn),
            unitText: resolveUnitText(from: txn),
            dosageFormCode: nil,
            dosageFormText: drug.drug_type,
            prescriptionNumber: txn.rx_no,
            pharmacistId: user?.user_id,
            pharmacistFamilyName: nil,
            pharmacistGivenName: user?.name,
            substituteCode: txn.is_substitute ? "1" : "0",
            deliverToLocation: user?.pharmacy_name,
            needsHumanReview: nil,
            dispensingNotes: txn.note,
            lotNumber: txn.lot_no,
            expirationDate: txn.expiry,
            substanceManufacturerName: nil,
            cellId: nil,
            cellLocation: nil
        )
        
        // MARK: ORDER
        let order = OrderData(
            orderControl: "RE",
            placerOrderId: txn.rx_no ?? "",
            placerOrderNamespace: config.sendingFacility,
            fillerOrderId: nil,
            fillerOrderNamespace: nil,
            orderStatus: txn.status,
            orderDateTime: timestamp,
            orderingProviderId: user?.user_id,
            orderingProviderFamilyName: nil,
            orderingProviderGivenName: user?.name,
            orderingFacility: config.sendingFacility
        )
        
        // MARK: NOTE (Partial / Full / I OWE YOU)
        let note = NoteData(
            setId: "1",
            sourceOfComment: "L",
            comment: buildCompletionNote(
                requested: requestedQty,
                dispensed: dispensedQty
            ),
            commentType: "INFO"
        )
        
        // MARK: OBX
        let auditOBX = buildAuditOBX(user: user)
        let imageOBX = buildImageOBX(txn: txn)

        
        let allOBX = auditOBX + imageOBX
        
        // MARK: MESSAGE
        let message = CompleteHL7Message(
            messageId: messageId,
            messageType: "RDS",
            triggerEvent: "O13",
            timestamp: timestamp,
            sendingFacility: config.sendingFacility,
            header: header,
            patient: buildPatient(txn: txn),
            visit: nil,
            order: order,
            medications: [],
            routes: [],
            components: [],
            dispenses: [dispense],
            equipment: nil,
            inventoryItems: [],
            inventory: nil,
            acknowledgment: nil,
            notes: [note],
            customSegments: [],
            obxSegments: allOBX,
            errors: []
        )
        
        return message.toHL7String()
    }
}

// MARK: - OBX BUILDERS
private func buildAuditOBX(user: UserEntity?) -> [ObservationData] {
    
    let timestamp = currentHL7Timestamp()
    
    return [
        ObservationData(
            setId: "1",
            valueType: "ST",
            observationId: "USER_ID",
            observationText: nil,
            codingSystem: nil,
            observationValue: user?.user_id ?? "",
            resultStatus: "F"
        ),
        ObservationData(
            setId: "2",
            valueType: "TS",
            observationId: "TIMESTAMP",
            observationText: nil,
            codingSystem: nil,
            observationValue: timestamp,
            resultStatus: "F"
        )
    ]
}

private func buildImageOBX(txn: PillCountTransactionEntity) -> [ObservationData] {
    
    guard let details = txn.pillCountTransactionDetails as? Set<PillCountTransactionDetailsEntity> else {
        return []
    }
    
    var obxList: [ObservationData] = []
    var index = 10
    
    for detail in details where !detail.is_deleted {
        
        guard let imagePath = detail.image_path else { continue }
        
        let type = mapType(detail.type ?? "UNKNOWN")
        
        obxList.append(
            ObservationData(
                setId: "\(index)",
                valueType: "ST",
                observationId: "IMAGE_\(type)",
                observationText: type,
                codingSystem: "",
                observationValue: imagePath,
                resultStatus: "F"
            )
        )
        
        index += 1
    }
    
    // txn level image
    if let txnImage = txn.barcode_image {
        obxList.append(
            ObservationData(
                setId: "\(index)",
                valueType: "ST",
                observationId: "IMAGE_FINAL",
                observationText: "FINAL",
                codingSystem: "",
                observationValue: txnImage,
                resultStatus: "F"
            )
        )
    }
    
    return obxList
}




// MARK: - HELPERS

private func buildCompletionNote(
    requested: Int,
    dispensed: Int
) -> String {
    
    let remaining = requested - dispensed
    
    if dispensed == 0 {
        return "NO FILL - I OWE YOU \(requested)"
    }
    
    if dispensed < requested {
        return "PARTIAL FILL - DISPENSED: \(dispensed) | REMAINING: \(remaining)"
    }
    
    return "FULL FILL - DISPENSED: \(dispensed)"
}

private func calculateDispensed(from txn: PillCountTransactionEntity) -> Int {
    
    guard let details = txn.pillCountTransactionDetails as? Set<PillCountTransactionDetailsEntity> else {
        return Int(txn.target_count)
    }
    
    let total = details
        .filter { !$0.is_deleted }
        .map { Int($0.pill_count) }
        .reduce(0, +)
    
    return total > 0 ? total : Int(txn.target_count)
}

private func mapType(_ type: String) -> String {
    switch type {
    case "CONTAINER_INITIATE": return "CONTAINER_INIT"
    case "TARGET_VERIFICATION": return "TARGET"
    case "TARGET_REVERIFICATION": return "TARGET_RECHECK"
    case "VIAL": return "VIAL"
    case "CONTAINER_PENDING": return "PENDING"
    default: return type
    }
}

private func resolveUnitCode(from txn: PillCountTransactionEntity) -> String {
    return "TAB"
}

private func resolveUnitText(from txn: PillCountTransactionEntity) -> String {
    return "Tablet"
}

private func currentHL7Timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter.string(from: Date())
}

private func buildPatient(txn: PillCountTransactionEntity) -> PatientData? {
    
    guard let name = txn.patient_name else { return nil }
    
    let parts = name.split(separator: " ")
    
    return PatientData(
        patientId: txn.rx_no ?? UUID().uuidString,
        patientIdAssigningAuthority: nil,
        patientIdType: "MR",
        familyName: parts.last.map(String.init),
        givenName: parts.first.map(String.init),
        middleName: nil,
        dateOfBirth: nil,
        sex: nil,
        streetAddress: nil,
        city: nil,
        state: nil,
        zipCode: nil,
        country: nil
    )
}
