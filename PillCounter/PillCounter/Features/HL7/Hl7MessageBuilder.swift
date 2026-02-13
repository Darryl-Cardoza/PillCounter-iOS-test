//
//  Hl7MessageBuilder.swift
//  PillCounter
//
//  Created by Bhushan Patil on 12/02/26.
//

import Foundation
import ComposeApp

final class HL7MessageBuilder {

//    static let shared = HL7MessageBuilder()
//
//    private init() {}
//
//    // MARK: DISPENSE (RDS O13)
//
//    func buildDispenseMessage(
//        txn: PillCountTransactionEntity,
//        txnDetails: [PillCountTransactionDetailsEntity],
//        drugCode: String,
//        drugName: String,
//        pharmacistId: String?,
//        pharmacistName: String?,
//        location: String?
//    ) -> CompleteHL7Message {
//
//        let now = timestamp()
//        let totalCount = txnDetails.reduce(0) { $0 + Int($1.pill_count) }
//
//        let header = MessageHeaderData(
//            fieldSeparator: "|",
//            encodingCharacters: "^~\\&",
//            sendingApplication: "PillCounter",
//            sendingFacility: "ROBOT",
//            receivingApplication: "PMS",
//            receivingFacility: "PHARMACY",
//            messageDateTime: now,
//            messageType: "RDS",
//            triggerEvent: "O13",
//            messageControlId: String(Date().timeIntervalSince1970),
//            processingId: "P",
//            versionId: "2.5",
//            countryCode: "91"
//        )
//
//        let  patient = PatientData(
//                 patientId = txn.rxNo ?: txn.txnId.toString()
//             ),
//
//
//        let order = Ordr(
//            orderControl: "RE",
//            orderStatus: "CM",
//            placerOrderId: txn.rx_no ?? "\(txn.txn_id)"
//        )
//
//        let dispense = DispenseData(
//            dispenseSubId: "1",
//            drugCode: drugCode,
//            drugName: drugName,
//            drugCodeSystem: "NDC",
//            dateTimeDispensed: now,
//            quantityDispensed: "\(totalCount)",
//            unitCode: "TAB",
//            unitText: "Tablets",
//            prescriptionNumber: txn.rx_no ?? "\(txn.txn_id)",
//            pharmacistId: pharmacistId,
//            pharmacistGivenName: pharmacistName,
//            pharmacistFamilyName: "",                 // REQUIRED
//            deliverToLocation: location,
//            dispensingNotes: txn.note,
//            lotNumber: txn.lot_no,
//            expirationDate: txn.expiry,
//            dosageFormCode: "",                       // REQUIRED
//            dosageFormText: "",                       // REQUIRED
//            substituteCode: "",                       // REQUIRED
//            needsHumanReview: "false",                  // REQUIRED
//            substanceManufacturerName: "",            // REQUIRED
//            cellId: "",                               // REQUIRED
//            cellLocation: ""                          // REQUIRED
//        )
//
//
//        return CompleteHL7Message(
//            messageId: String(Date().timeIntervalSince1970),
//            messageType: "RDS",
//            triggerEvent: "O13",
//            timestamp: now,
//            sendingFacility: "PillCounter",
//            header: header,
//            patient: patient,
//            visit: nil,
//            order: order,
//            medications: [],
//            routes: [],
//            components: [],
//            dispenses: [dispense],
//            equipment: nil,
//            inventoryItems: [],
//            inventory: nil,
//            acknowledgment: nil,
//            notes: [],
//            customSegments: [],
//            obxSegments: [],
//            errors: []
//        )
//    }
//
//    private func timestamp() -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "yyyyMMddHHmmss"
//        return formatter.string(from: Date())
//    }
}
