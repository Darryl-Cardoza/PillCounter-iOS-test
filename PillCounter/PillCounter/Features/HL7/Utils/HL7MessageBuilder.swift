//
//  HL7CompletionBuilder.swift
//  PillCounter
//

import Hl7Core
import UIKit
import Darwin

struct HL7Config {
    let sendingApplication: String
    let sendingFacility: String
    let receivingApplication: String
    let receivingFacility: String
    let versionId: String
}


// MARK: - Builder

final class HL7CompletionBuilder {
    let versionId = "2.5"

    private let builder: HL7Builder = HL7Builder.companion.builder()
        .defaultVersion(version: "2.5")
        .build()

    // MARK: - Dispense Message (RDS O13)
    func buildCompletionMessage(
        txn: PillCountTransactionEntity,
        user: UserEntity?
    ) -> String {

        let now = DateUtils.currentTimestamp()
        let messageId = "\(Int64(Date().timeIntervalSince1970 * 1000))"

        let allDetails = pillCountDetails(from: txn)
        let details = allDetails.filter { !$0.is_deleted }
        let totalCount = details
            .map { Int($0.pill_count) }
            .reduce(0, +)

        guard let drug = txn.drug else {
            fatalError("Drug missing")
        }

        let orderId = txn.rx_no ?? "\(txn.txn_id)"

        let message = builder.rdsO13 { scope in
            scope.msh { msh in
                msh.sendingApplication = "PillCounter"
                msh.sendingFacility = "ROBOT"
                msh.receivingApplication = "PMS"
                msh.receivingFacility = "PHARMACY"
                msh.dateTimeOfMessage = now
                msh.messageControlId = messageId
                msh.processingId = "P"
                msh.versionId = self.versionId
            }

            scope.orc { orc in
                orc.orderControl = "RE"
                orc.placerOrderNumber = orderId
                orc.orderStatus = "CM"
            }

            scope.pid { pid in
                pid.patientId = orderId
            }

            scope.rxd { rxd in
                rxd.dispenseGiveCode = drug.ndc ?? ""
                rxd.dispenseGiveName = drug.drug_name ?? ""
                rxd.dispenseGiveCodeSystem = "NDC"
                rxd.dateTimeDispensed = now
                rxd.actualDispenseAmount = "\(totalCount)"
                rxd.actualDispenseUnits = "TAB"
                rxd.prescriptionNumber = orderId
                rxd.lotNumber = txn.lot_no
                rxd.expirationDate = txn.expiry
                rxd.dispensingProviderId = user?.user_id
                rxd.dispenseSubIdCounter = "1"
            }

            for note in self.buildCommonNotes(txn: txn, totalCount: totalCount) {
                scope.nte { nte in
                    nte.setId = note.setId
                    nte.sourceOfComment = note.sourceOfComment
                    nte.comment = note.comment
                    nte.commentType = note.commentType
                }
            }

            for obx in self.buildImageOBX(
                txn: txn,
                details: details,
                observationId: "DISP_IMG",
                label: "Dispense Image"
            ) {
                scope.obx { builder in
                    builder.setId = obx.setId
                    builder.valueType = obx.valueType
                    builder.observationId = obx.observationId
                    builder.observationText = obx.observationText
                    builder.observationValue = obx.observationValue
                    builder.resultStatus = obx.resultStatus
                    builder.units = obx.units
                }
            }
        }

        return message.encode()
    }

    // MARK: - Inventory Response (INR U05)
    func buildInventoryMessage(
        batch: BatchCountEntity,
        user: UserEntity?
    ) -> String {

        let now = DateUtils.currentTimestamp()
        let messageId = "RES\(Int(Date().timeIntervalSince1970))"
        let requestId = batch.req_id_from_pms ?? "REQ\(batch.batch_id)"
        let orderId = batch.bucket_id ?? ""

        let txns = TransactionStore.shared.fetchByBatch(batchId: batch.batch_id)

        // MARK: GROUPING
        struct Key: Hashable {
            let ndc: String; let name: String; let lot: String; let expiry: String
        }
        var grouped: [Key: (opened: Int32, sealed: Int32)] = [:]

        for txn in txns {
            guard let drug = txn.drug else { continue }
            let key = Key(
                ndc: drug.ndc ?? "", name: drug.drug_name ?? "",
                lot: txn.lot_no ?? "", expiry: txn.expiry ?? ""
            )
            var e = grouped[key] ?? (0, 0)
            e.opened += txn.loose_qty
            e.sealed += txn.bottle_qty * drug.package_qty
            grouped[key] = e
        }

        let message = builder.inrU05 { scope in
            scope.msh { msh in
                msh.sendingApplication = "PILLCOUNTER"
                msh.sendingFacility = "STORE"
                msh.receivingApplication = "PMS"
                msh.receivingFacility = "PHARMACY"
                msh.dateTimeOfMessage = now
                msh.messageControlId = messageId
                msh.processingId = "P"
                msh.versionId = self.versionId
            }

            scope.orc { orc in
                orc.orderControl = "RE"
                orc.placerOrderNumber = orderId
            }

            var index: Int32 = 1
            for (key, value) in grouped {
                let total = value.opened + value.sealed

                scope.inv { inv in
                    inv.setId = "\(index)"
                    // INV-2.1 (substance code / NDC) has no dedicated property on the
                    // current INVBuilder — reusing inventoryLocationIdentifier as a
                    // stopgap until the library exposes a proper substanceCode field.
                    inv.inventoryLocationIdentifier = key.ndc
                    inv.substanceCodeSystem = "NDC"
                    inv.substanceName = key.name.isEmpty ? nil : key.name
                    inv.inventoryOnHandQuantity = "\(total)"
                }

                if value.opened == 0 && value.sealed == 0 {
                    scope.zin { zin in
                        zin.setId = "\(index)"
                        zin.dispenseType = "NA"
                        zin.quantity = "0"
                    }
                } else {
                    if value.opened > 0 {
                        scope.zin { zin in
                            zin.setId = "\(index)"
                            zin.dispenseType = "OPENED"
                            zin.quantity = "\(value.opened)"
                            zin.lotNumber = key.lot.isEmpty ? nil : key.lot
                            zin.expiry = key.expiry.isEmpty ? nil : key.expiry
                        }
                    }
                    if value.sealed > 0 {
                        scope.zin { zin in
                            zin.setId = "\(index)"
                            zin.dispenseType = "SEALED"
                            zin.quantity = "\(value.sealed)"
                            zin.lotNumber = key.lot.isEmpty ? nil : key.lot
                            zin.expiry = key.expiry.isEmpty ? nil : key.expiry
                        }
                    }
                }

                index += 1
            }
        }

        // The ACK for the originating request (MSA-2 = requestId) is a separate
        // message from this INR^U05 response; build/send it via `HL7.ack(message:)`
        // or `HL7Builder().ack { ... }` where the inbound request is parsed, not here.
        _ = requestId

        return message.encode()
    }
}

// MARK: - Shared Private Helpers
private extension HL7CompletionBuilder {

    // MARK: Image OBX Builder
    struct ObxRow {
        let setId: String
        let valueType: String
        let observationId: String
        let observationText: String?
        let observationValue: String
        let resultStatus: String
        let units: String?
    }

    func buildImageOBX(
        txn: PillCountTransactionEntity,
        details: [PillCountTransactionDetailsEntity],
        observationId: String,
        label: String
    ) -> [ObxRow] {

        var obxList: [ObxRow] = []

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

            obxList.append(
                ObxRow(
                    setId: "\(index + 1)",
                    valueType: "ST",
                    observationId: observationId,
                    observationText: "\(label) \(index + 1)",
                    observationValue: observationValue,
                    resultStatus: "F",
                    units: nil
                )
            )
        }

        // Barcode Image (same as Android)
        if let barcodePath = txn.barcode_image,
           !barcodePath.isEmpty {

            let fileName = (barcodePath as NSString).lastPathComponent

            obxList.append(
                ObxRow(
                    setId: "\(obxList.count + 1)",
                    valueType: "ST",
                    observationId: observationId,
                    observationText: "Barcode Image",
                    observationValue: "count=0|type=SCAN|image=\(fileName)",
                    resultStatus: "F",
                    units: nil
                )
            )
        }

        return obxList
    }

    // MARK: Notes Builder
    struct NoteRow {
        let setId: String
        let sourceOfComment: String
        let comment: String
        let commentType: String
    }

    func buildCommonNotes(
        txn: PillCountTransactionEntity,
        totalCount: Int
    ) -> [NoteRow] {

        var notes: [NoteRow] = []
        var index = 1

        notes.append(
            NoteRow(
                setId: "\(index)",
                sourceOfComment: "L",
                comment: "Transaction completed",
                commentType: "INFO"
            )
        )
        index += 1

        notes.append(
            NoteRow(
                setId: "\(index)",
                sourceOfComment: "L",
                comment: "Total Count: \(totalCount)",
                commentType: "INFO"
            )
        )
        index += 1

        notes.append(
            NoteRow(
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
                NoteRow(
                    setId: "\(index)",
                    sourceOfComment: "L",
                    comment: note,
                    commentType: "INFO"
                )
            )
        }

        return notes
    }

    // MARK: Detail Extractor

    func pillCountDetails(
        from txn: PillCountTransactionEntity
    ) -> [PillCountTransactionDetailsEntity] {
        return (txn.pillCountTransactionDetails as? Set<PillCountTransactionDetailsEntity>)
            .map { Array($0) } ?? []
    }
}
