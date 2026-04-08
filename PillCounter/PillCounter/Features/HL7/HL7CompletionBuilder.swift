//
//  HL7CompletionBuilder.swift
//  PillCounter
//

import ComposeApp
import UIKit
import Darwin

// MARK: - Constants

private enum HL7BuilderConstants {
    static let imagePort = 8443
    static let encodingCharacters = "^~\\&"
    static let processingId = "P"
    static let versionId = "2.5"
}

// MARK: - Config

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
            sendingApplication: "PillCounter",
            sendingFacility: "PillCounter-\(UIDevice.current.model)",
            receivingApplication: "PMS",
            receivingFacility: "PHARMACY",
            versionId: HL7BuilderConstants.versionId
        )
    }
}

// MARK: - Native Network Utils
// iOS equivalent of Android's NetworkUtils.getLocalIpAddress()

enum iOSNetworkUtils {

    /// Returns the device's current Wi-Fi / LAN IPv4 address, or nil if unavailable.
    /// Prefers en0 (Wi-Fi), falls back to en1. Skips loopback (127.x.x.x).
    static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // en0 = Wi-Fi, en1 = Ethernet adapter (iPad etc.)
                if name == "en0" || (address == nil && name == "en1") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        address = String(cString: hostname)
                    }
                    // Stop as soon as we find en0
                    if name == "en0" { break }
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return address
    }
}

// MARK: - Builder

final class HL7CompletionBuilder {

    // MARK: - Dispense Message (RDS O13)

    func buildCompletionMessage(
        txn: PillCountTransactionEntity,
        user: UserEntity?
    ) -> String {

        let now = currentHL7Timestamp()
        let config = HL7ConfigProvider.getConfig(user: user)
        let messageId = "\(Int64(Date().timeIntervalSince1970 * 1000))"

        let details = pillCountDetails(from: txn)
        let totalCount = details
            .filter { !$0.is_deleted }
            .map { Int($0.pill_count) }
            .reduce(0, +)

        // MARK: Header
        let header = buildHeader(
            type: "RDS",
            trigger: "O13",
            time: now,
            config: config,
            messageId: messageId
        )

        // MARK: Drug
        guard let drug = txn.drug else {
            fatalError("Drug mapping missing for txn_id: \(txn.txn_id)")
        }

        // MARK: Dispense
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
            dosageFormText: drug.drug_type,
            prescriptionNumber: txn.rx_no,
            pharmacistId: user?.user_id,
            pharmacistFamilyName: nil,
            pharmacistGivenName: user?.fname ?? "",
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

        // MARK: Order
        let order = OrderData(
            orderControl: "RE",
            placerOrderId: txn.rx_no ?? "\(txn.txn_id)",
            placerOrderNamespace: config.sendingFacility,
            fillerOrderId: nil,
            fillerOrderNamespace: nil,
            orderStatus: "CM",
            orderDateTime: now,
            orderingProviderId: user?.user_id,
            orderingProviderFamilyName: nil,
            orderingProviderGivenName: user?.fname,
            orderingFacility: config.sendingFacility
        )

        // MARK: OBX — Images
        let imageOBX = buildImageOBX(
            txn: txn,
            details: details,
            observationId: "DISP_IMG",
            label: "Dispense Image"
        )

        // MARK: Notes
        let notes = buildCommonNotes(txn: txn, totalCount: totalCount)

        // MARK: Message
        let message = CompleteHL7Message(
            messageId: messageId,
            messageType: "RDS",
            triggerEvent: "O13",
            timestamp: now,
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
            notes: notes,
            customSegments: [],
            obxSegments: imageOBX,
            errors: []
        )

        return message.toHL7String()
    }

    // MARK: - Inventory Message (INU U05)

    func buildInventoryMessage(
        txn: PillCountTransactionEntity,
        user: UserEntity?
    ) -> String {

        let now = currentHL7Timestamp()
        let config = HL7ConfigProvider.getConfig(user: user)
        let messageId = "\(Int64(Date().timeIntervalSince1970 * 1000))"

        guard let drug = txn.drug else {
            fatalError("Drug mapping missing for txn_id: \(txn.txn_id)")
        }

        let details = pillCountDetails(from: txn)
        let totalCount = details
            .filter { !$0.is_deleted }
            .map { Int($0.pill_count) }
            .reduce(0, +)

        // MARK: Header
        let header = buildHeader(
            type: "INU",
            trigger: "U05",
            time: now,
            config: config,
            messageId: messageId
        )

        // MARK: InventoryBinData
        // Full initializer per ComposeApp Obj-C header:
        // init(substanceId:substanceName:substanceCodeSystem:substanceStatus:
        //      cellId:cellLocation:quantityOnHand:availableQuantity:
        //      quantityUnitCode:quantityUnitText:expirationDate:lotNumber:
        //      manufacturerName:supplierName:onOrderQuantity:)
        let inventoryBin = InventoryBinData(
            substanceId: drug.ndc ?? "",
            substanceName: drug.drug_name ?? "",
            substanceCodeSystem: "NDC",
            substanceStatus: nil,
            cellId: nil,
            cellLocation: nil,
            quantityOnHand: "\(totalCount)",
            availableQuantity: "\(totalCount)",
            quantityUnitCode: "TAB",
            quantityUnitText: "Tablets",
            expirationDate: txn.expiry,
            lotNumber: txn.lot_no,
            manufacturerName: nil,
            supplierName: nil,
            onOrderQuantity: nil
        )

        // MARK: InventoryData
        // Full initializer per ComposeApp Obj-C header:
        // init(equipmentId:equipmentIdNamespace:eventDateTime:
        //      equipmentState:equipmentName:equipmentType:bins:)
        let inventory = InventoryData(
            equipmentId: "ROBOT1",
            equipmentIdNamespace: nil,
            eventDateTime: now,
            equipmentState: nil,
            equipmentName: nil,
            equipmentType: nil,
            bins: [inventoryBin]
        )

        // MARK: OBX — Images
        let imageOBX = buildImageOBX(
            txn: txn,
            details: details,
            observationId: "INV_IMG",
            label: "Inventory Image"
        )

        // MARK: Notes
        let notes = buildCommonNotes(txn: txn, totalCount: totalCount)

        // MARK: Message
        let message = CompleteHL7Message(
            messageId: messageId,
            messageType: "INU",
            triggerEvent: "U05",
            timestamp: now,
            sendingFacility: config.sendingFacility,
            header: header,
            patient: nil,
            visit: nil,
            order: nil,
            medications: [],
            routes: [],
            components: [],
            dispenses: [],
            equipment: nil,
            inventoryItems: [],
            inventory: inventory,
            acknowledgment: nil,
            notes: notes,
            customSegments: [],
            obxSegments: imageOBX,
            errors: []
        )

        return message.toHL7String()
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
            encodingCharacters: HL7BuilderConstants.encodingCharacters,
            sendingApplication: config.sendingApplication,
            sendingFacility: config.sendingFacility,
            receivingApplication: config.receivingApplication,
            receivingFacility: config.receivingFacility,
            messageDateTime: time,
            messageType: type,
            triggerEvent: trigger,
            messageControlId: messageId,
            processingId: HL7BuilderConstants.processingId,
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
            
            let count = detail.pill_count ?? 0
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

// MARK: - Timestamp

private func currentHL7Timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter.string(from: Date())
}
