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

    /// Sourced from `AppStorageManager`: the terminal name identifies this
    /// station as the sending facility, and the configured PMS host name is
    /// used as the receiving facility since the PMS routes by that identity.
    static var current: HL7Config {
        HL7Config(
            sendingApplication: "DISPENSESURE",
            sendingFacility: AppStorageManager.shared.selectedTerminalName,
            receivingApplication: "PMS",
            receivingFacility: AppStorageManager.shared.pmsHostName,
            versionId: AppStorageManager.shared.hl7Version
        )
    }
}


// MARK: - Builder

final class HL7CompletionBuilder {
    let config: HL7Config
    private var versionId: String { config.versionId }
    private let builder: HL7Builder

    /// `config` defaults to values sourced from `AppStorageManager` (terminal
    /// name, PMS host name, HL7 version — the latter from `auth/me` →
    /// `settings.hl7_version`), so built messages always match what the
    /// connected PMS expects.
    init(config: HL7Config = .current) {
        self.config = config
        self.builder = HL7Builder.companion.builder()
            .defaultVersion(version: config.versionId)
            .build()
    }

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
                msh.sendingApplication = self.config.sendingApplication
                msh.sendingFacility = self.config.sendingFacility
                msh.receivingApplication = self.config.receivingApplication
                msh.receivingFacility = self.config.receivingFacility
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

            for zsn in self.buildZSN(txn: txn, details: details, drug: drug, now: now) {
                scope.zsn { builder in
                    builder.setId = zsn.setId
                    builder.nationalDrugCode = zsn.nationalDrugCode
                    builder.quantityFromThisStockItem = zsn.quantityFromThisStockItem
                    builder.captureSource = zsn.captureSource
                    builder.captureTimestamp = zsn.captureTimestamp
                    builder.transactionType = zsn.transactionType
                }
            }

            let zsv = self.buildZSV(txn: txn, drug: drug, now: now)
            scope.zsv { builder in
                builder.setId = zsv.setId
                builder.scannedNdc = zsv.scannedNdc
                builder.dispensedNdc = zsv.dispensedNdc
                builder.matchStrength = zsv.matchStrength
                builder.validationResult = zsv.validationResult
                builder.validator = zsv.validator
                builder.validationTimestamp = zsv.validationTimestamp
                builder.scanSource = zsv.scanSource
            }
        }

        return message.encode()
    }

    // MARK: - Inventory Response (INR U06, INV + ZAD)
    func buildInventoryMessage(
        batch: BatchCountEntity,
        user: UserEntity?
    ) -> String {

        let now = DateUtils.currentTimestamp()
        let messageId = "RES\(Int(Date().timeIntervalSince1970))"
        let requestId = batch.req_id_from_pms ?? "REQ\(batch.batch_id)"
        let orderId = batch.bucket_id ?? ""

        let stockTxns = StockTxnStore.shared.fetchByBatch(batchId: batch.batch_id)

        // MARK: GROUPING
        struct Key: Hashable {
            let ndc: String; let name: String; let lot: String; let expiry: String
        }
        var grouped: [Key: (opened: Int32, sealed: Int32)] = [:]

        for stockTxn in stockTxns {
            guard let drug = stockTxn.drug else { continue }
            let bottles = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
            for bottle in bottles {
                let key = Key(
                    ndc: drug.ndc ?? "", name: drug.drug_name ?? "",
                    lot: bottle.lot_no ?? "", expiry: bottle.exp_no ?? ""
                )
                var e = grouped[key] ?? (0, 0)
                e.opened += bottle.loose_qty
                e.sealed += bottle.bottle_qty * drug.package_qty
                grouped[key] = e
            }
        }

        let message = builder.inrU06 { scope in
            scope.msh { msh in
                msh.sendingApplication = self.config.sendingApplication
                msh.sendingFacility = self.config.sendingFacility
                msh.receivingApplication = self.config.receivingApplication
                msh.receivingFacility = self.config.receivingFacility
                msh.dateTimeOfMessage = now
                msh.messageControlId = messageId
                msh.processingId = "P"
                msh.versionId = self.versionId
            }

            scope.orc { orc in
                orc.orderControl = "RE"
                orc.placerOrderNumber = orderId
            }

            let grandTotal = grouped.values.reduce(Int32(0)) { $0 + $1.opened + $1.sealed }
            for note in self.buildCommonNotes(batch: batch, totalCount: grandTotal) {
                scope.nte { nte in
                    nte.setId = note.setId
                    nte.sourceOfComment = note.sourceOfComment
                    nte.comment = note.comment
                    nte.commentType = note.commentType
                }
            }

            var index: Int32 = 1
            for (key, value) in grouped {
                let total = value.opened + value.sealed

                scope.inv { inv in
                    inv.setId = "\(index)"
                    // INV-2.1 (substance code / NDC) has no dedicated property on the
                    // current INVBuilder — reusing inventoryLocationIdentifier as a
                    // stopgap until the library exposes a proper substanceCode field.
                    inv.substanceCode = key.ndc
                    inv.substanceCodeSystem = "NDC"
                    inv.substanceName = key.name.isEmpty ? nil : key.name
                    inv.inventoryOnHandQuantity = "\(total)"
                    inv.lotNumber = key.lot.isEmpty ? nil : key.lot
                    inv.expirationDate = key.expiry.isEmpty ? nil : key.expiry
                }

                scope.zad { zad in
                    zad.setId = "\(index)"
                    zad.adjustmentType = "CYCLE_COUNT"
                    zad.adjustmentQuantity = "\(total)"
                    zad.adjustmentReason = ZadReasonCode.shared.CYCLE_COUNT
                    zad.adjustmentDateTime = now
                    zad.approvedBy = user?.fname ?? "Unknown"
                }

                index += 1
            }
        }

        // The ACK for the originating request (MSA-2 = requestId) is a separate
        // message from this INR^U06 response; build/send it via `HL7.ack(message:)`
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

    // MARK: ZSN/ZSV Builders

    struct ZsnRow {
        let setId: String
        let nationalDrugCode: String?
        let quantityFromThisStockItem: String
        let captureSource: String
        let captureTimestamp: String
        let transactionType: String
    }

    func buildZSN(
        txn: PillCountTransactionEntity,
        details: [PillCountTransactionDetailsEntity],
        drug: DrugMasterEntity,
        now: String
    ) -> [ZsnRow] {
        return details.enumerated().map { index, detail in
            ZsnRow(
                setId: "\(index + 1)",
                nationalDrugCode: drug.ndc,
                quantityFromThisStockItem: "\(detail.pill_count)",
                captureSource: detail.is_manual ? ScanSource.shared.MANUAL : ScanSource.shared.UNKNOWN,
                captureTimestamp: now,
                transactionType: ZsnTransactionType.shared.DISPENSE
            )
        }
    }

    struct ZsvRow {
        let setId: String
        let scannedNdc: String?
        let dispensedNdc: String?
        let matchStrength: String?
        let validationResult: String
        let validator: String
        let validationTimestamp: String
        let scanSource: String
    }

    func buildZSV(
        txn: PillCountTransactionEntity,
        drug: DrugMasterEntity,
        now: String
    ) -> ZsvRow {
        return ZsvRow(
            setId: "1",
            scannedNdc: drug.ndc,
            dispensedNdc: drug.ndc,
            matchStrength: txn.is_ndc_verfied ? ZsvMatchStrength.shared.EXACT : nil,
            validationResult: txn.is_ndc_verfied ? ZsvValidationResult.shared.MATCH : ZsvValidationResult.shared.MISMATCH,
            validator: "PillCounter",
            validationTimestamp: now,
            scanSource: ScanSource.shared.UNKNOWN
        )
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

        var comment = "Transaction Id: \(txn.txn_id) | Status: Completed | Total Count: \(totalCount)"

        if let note = txn.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            comment += " | Note: \(note)"
        }

        return [
            NoteRow(
                setId: "1",
                sourceOfComment: "L",
                comment: comment,
                commentType: "INFO"
            )
        ]
    }

    func buildCommonNotes(
        batch: BatchCountEntity,
        totalCount: Int32
    ) -> [NoteRow] {

        var comment = "Batch Id: \(batch.batch_id) | Status: Completed | Total Count: \(totalCount)"

        if let note = batch.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            comment += " | Note: \(note)"
        }

        return [
            NoteRow(
                setId: "1",
                sourceOfComment: "L",
                comment: comment,
                commentType: "INFO"
            )
        ]
    }

    // MARK: Detail Extractor

    func pillCountDetails(
        from txn: PillCountTransactionEntity
    ) -> [PillCountTransactionDetailsEntity] {
        return (txn.pillCountTransactionDetails as? Set<PillCountTransactionDetailsEntity>)
            .map { Array($0) } ?? []
    }
}
