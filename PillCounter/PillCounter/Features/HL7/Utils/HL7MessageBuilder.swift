//
//  HL7CompletionBuilder.swift
//  PillCounter
//

import ComposeApp
import UIKit
import Darwin

//// MARK: - Constants
//
//private enum HL7BuilderConstants {
//    static let imagePort = 8443
//    static let encodingCharacters = "^~\\&"
//    static let processingId = "P"
//    static let versionId = "2.5"
//}




struct HL7Config {
    let sendingApplication: String
    let sendingFacility: String
    let receivingApplication: String
    let receivingFacility: String
    let versionId: String
}


// MARK: - Builder

final class HL7CompletionBuilder {
    let encodingCharacters = "2.5"

    // MARK: - Dispense Message (RDS O13)
    func buildCompletionMessage(
        txn: PillCountTransactionEntity,
        user: UserEntity?
    ) -> String {

        let now = DateUtils.currentTimestamp()
        let messageId = "\(Int64(Date().timeIntervalSince1970 * 1000))"

        let details = pillCountDetails(from: txn)
        let totalCount = details
            .filter { !$0.is_deleted }
            .map { Int($0.pill_count) }
            .reduce(0, +)

        guard let drug = txn.drug else {
            fatalError("Drug missing")
        }

        let dispense = DispenseData(
            dispenseSubId: "1",
            drugCode: drug.ndc ?? "",
            drugName: drug.drug_name ?? "",
            drugCodeSystem: "NDC",
            dateTimeDispensed: now,
            quantityDispensed: "\(totalCount)",
            unitCode: "TAB",
            unitText: "Tablets",
            dosageFormCode: nil,
            dosageFormText: nil,
            prescriptionNumber: txn.rx_no ?? "\(txn.txn_id)",
            pharmacistId: user?.user_id,
            pharmacistFamilyName: nil,
            pharmacistGivenName: user?.fname,
            substituteCode: nil,
            deliverToLocation: user?.pharmacy_name,
            needsHumanReview: nil,
            dispensingNotes: txn.note,
            lotNumber: txn.lot_no,
            expirationDate: txn.expiry,
            substanceManufacturerName: nil,
            cellId: nil,
            cellLocation: nil
        )

        let order = OrderData(
            orderControl: "RE",
            placerOrderId: txn.rx_no ?? "\(txn.txn_id)",
            placerOrderNamespace: nil,
            fillerOrderId: nil,
            fillerOrderNamespace: nil,
            orderStatus: "CM",
            orderDateTime: nil,
            orderingProviderId: nil,
            orderingProviderFamilyName: nil,
            orderingProviderGivenName: nil,
            orderingFacility: nil
        )

        let patient = PatientData(
            patientId: txn.rx_no ?? "\(txn.txn_id)",
            patientIdAssigningAuthority: nil,
            patientIdType: nil,
            familyName: nil,
            givenName: nil,
            middleName: nil,
            dateOfBirth: nil,
            sex: nil,
            streetAddress: nil,
            city: nil,
            state: nil,
            zipCode: nil,
            country: nil
        )

        let message = CompleteHL7Message(
            messageId: messageId,
            messageType: "RDS",
            triggerEvent: "O13",
            timestamp: now,
            sendingFacility: "ROBOT",

            header: buildHeaderStyle(
                type: "RDS",
                trigger: "O13",
                time: now,
                messageId: messageId
            ),

            patient: patient,
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
            notes: buildCommonNotes(txn: txn, totalCount: totalCount),
            customSegments: [],
            obxSegments: buildImageOBX(
                txn: txn,
                details: details,
                observationId: "DISP_IMG",
                label: "Dispense Image"
            ),
            errors: []
        )

        return message.toHL7String()
    }
    
    func buildHeaderStyle(
        type: String,
        trigger: String,
        time: String,
        messageId: String
    ) -> MessageHeaderData {

        return MessageHeaderData(
            fieldSeparator: "|",
            encodingCharacters: "^~\\&",
            sendingApplication: "PillCounter",
            sendingFacility: "ROBOT",             
            receivingApplication: "PMS",
            receivingFacility: "PHARMACY",
            messageDateTime: time,
            messageType: type,
            triggerEvent: trigger,
            messageControlId: messageId,
            processingId: "P",
            versionId: "2.5",
            countryCode: nil
        )
    }

  
    func buildInventoryMessage(
        batch: BatchCountEntity,
        user: UserEntity?
    ) -> String {

        let now = DateUtils.currentTimestamp()
        let messageId = "RES\(Int(Date().timeIntervalSince1970))"

        let requestId = batch.req_id_from_pms ?? "REQ\(batch.batch_id)"
        let orderId = batch.bucket_id ?? ""

        let txns = TransactionDAO.shared.fetchByBatch(batchId: batch.batch_id)

        // MARK: GROUPING
        struct Key: Hashable {
            let ndc: String
            let name: String
            let lot: String
            let expiry: String
        }

        var grouped: [Key: (opened: Int32, sealed: Int32)] = [:]

        for txn in txns {

            guard let drug = txn.drug else { continue }

            let ndc = drug.ndc ?? ""
            let name = drug.drug_name ?? ""
            let lot = txn.lot_no ?? ""
            let expiry = txn.expiry ?? ""
            let packageQty = drug.package_qty

            let opened = txn.loose_qty
            let sealed = txn.bottle_qty * packageQty

            let key = Key(ndc: ndc, name: name, lot: lot, expiry: expiry)

            var existing = grouped[key] ?? (0, 0)
            existing.opened += opened
            existing.sealed += sealed
            grouped[key] = existing
        }

        // MARK: BUILD HL7 STRING

        var hl7 = ""

        //  HEADER
        hl7 += "MSH|^~\\&|PILLCOUNTER|STORE|PMS|PHARMACY|\(now)||INR^U05|\(messageId)|P|2.5\n"
        hl7 += "MSA|AA|\(requestId)\n"
        hl7 += "ORC|RE|\(orderId)\n\n"

        var index = 1

        for (key, value) in grouped {

            let total = value.opened + value.sealed

            // INV
            hl7 += "INV|\(index)|\(key.ndc)^\(key.name)||||||||||\(total)|||||\n"

            //  ZIN
            if value.opened == 0 && value.sealed == 0 {
                hl7 += "ZIN|\(index)|NA|0||\n"
            } else {
                if value.opened > 0 {
                    hl7 += "ZIN|\(index)|OPENED|\(value.opened)|\(key.lot)|\(key.expiry)\n"
                }
                if value.sealed > 0 {
                    hl7 += "ZIN|\(index)|SEALED|\(value.sealed)|\(key.lot)|\(key.expiry)\n"
                }
            }

            hl7 += "\n"
            index += 1
        }

        return hl7
    }
}

// MARK: - Shared Private Helpers
private extension HL7CompletionBuilder {

    // MARK: Header Builder

    func buildHeader(
        type: String,
        trigger: String,
        time: String,
        config: HL7Config,
        messageId: String
    ) -> MessageHeaderData {
        return MessageHeaderData(
            fieldSeparator: "|",
            encodingCharacters: encodingCharacters,
            sendingApplication: config.sendingApplication,
            sendingFacility: config.sendingFacility,
            receivingApplication: config.receivingApplication,
            receivingFacility: config.receivingFacility,
            messageDateTime: time,
            messageType: type,
            triggerEvent: trigger,
            messageControlId: messageId,
            processingId: encodingCharacters,
            versionId: config.versionId,
            countryCode: nil
        )
    }

    // MARK: Image OBX Builder
    func buildImageOBX(
        txn: PillCountTransactionEntity,
        details: [PillCountTransactionDetailsEntity],
        observationId: String,
        label: String
    ) -> [ObservationData] {
        
        var obxList: [ObservationData] = []
        
        for (index, detail) in details.enumerated() {
            
            let count = detail.pill_count
            let type = detail.type ?? "UNKNOWN"
            
            let fileName: String
            if let path = detail.image_path {
                fileName = (path as NSString).lastPathComponent
            } else {
                fileName = ""
            }
            
            let observationValue = "count=\(count)|type=\(type)|image=\(fileName)"
            
            let obx = ObservationData(
                setId: "\(index + 1)",
                valueType: "ST",
                observationId: observationId,
                observationText: "\(label) \(index + 1)",
                codingSystem: "",
                observationValue: observationValue,
                resultStatus: "F"
            )
            
            obxList.append(obx)
        }
        
        // Barcode Image (same as Android)
        if let barcodePath = txn.barcode_image,
           !barcodePath.isEmpty {
            
            let fileName = (barcodePath as NSString).lastPathComponent
            
            let barcodeObx = ObservationData(
                setId: "\(obxList.count + 1)",
                valueType: "ST",
                observationId: observationId,
                observationText: "Barcode Image",
                codingSystem: "",
                observationValue: "count=0|type=SCAN|image=\(fileName)",
                resultStatus: "F"
            )
            
            obxList.append(barcodeObx)
        }
        
        return obxList
    }

    // MARK: Notes Builder
    func buildCommonNotes(
        txn: PillCountTransactionEntity,
        totalCount: Int
    ) -> [NoteData] {
        
        var notes: [NoteData] = []
        var index = 1

        notes.append(
            NoteData(
                setId: "\(index)",
                sourceOfComment: "L",
                comment: "Transaction completed",
                commentType: "INFO"
            )
        )
        index += 1

        notes.append(
            NoteData(
                setId: "\(index)",
                sourceOfComment: "L",
                comment: "Total Count: \(totalCount)",
                commentType: "INFO"
            )
        )
        index += 1

        notes.append(
            NoteData(
                setId: "\(index)",
                sourceOfComment: "L",
                comment: "Transaction Id: \(txn.txn_id)",
                commentType: "INFO"
            )
        )
        index += 1

        if let note = txn.note,
           !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

            notes.append(
                NoteData(
                    setId: "\(index)",
                    sourceOfComment: "L",
                    comment: note,
                    commentType: "INFO"
                )
            )
        }

        return notes
    }
    
    // MARK: Patient Builder

    func buildPatient(txn: PillCountTransactionEntity) -> PatientData? {
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
    
    func buildZINSegments(
        invIndex: Int,
        opened: Int32,
        sealed: Int32,
        lot: String?,
        expiry: String?
    ) -> [CustomSegmentData] {

        func makeZIN(_ type: String, _ qty: Int32) -> CustomSegmentData {
            CustomSegmentData(
                segmentType: "ZIN",
                field1: "\(invIndex)",
                field2: type,
                field3: "\(qty)",
                field4: lot ?? "",
                field5: expiry ?? "",
                field6: nil,
                allFields: [
                    1: "\(invIndex)",
                    2: type,
                    3: "\(qty)",
                    4: lot ?? "",
                    5: expiry ?? ""
                ]
            )
        }

        if opened == 0 && sealed == 0 {
            return [makeZIN("NA", 0)]
        }

        var segments: [CustomSegmentData] = []

        if opened > 0 {
            segments.append(makeZIN("OPENED", opened))
        }

        if sealed > 0 {
            segments.append(makeZIN("SEALED", sealed))
        }

        return segments
    }

    // MARK: Detail Extractor

    func pillCountDetails(
        from txn: PillCountTransactionEntity
    ) -> [PillCountTransactionDetailsEntity] {
        return (txn.pillCountTransactionDetails as? Set<PillCountTransactionDetailsEntity>)
            .map { Array($0) } ?? []
    }

    // MARK: Image URL Builder
    // Mirrors Android: "https://deviceIp:port/images/fileName"

    func buildImageUrl(deviceIp: String, fileName: String, port: Int) -> String {
//        return "https://\(deviceIp):\(port)/images/\(fileName)"
        return "\(fileName)"
    }
}





