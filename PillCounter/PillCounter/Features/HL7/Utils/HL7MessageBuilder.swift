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
    let format: Hl7Format

    /// Sourced from `AppStorageManager`: the terminal name identifies this
    /// station as the sending facility, and the configured PMS host name is
    /// used as the receiving facility since the PMS routes by that identity.
    /// `format` (server-driven, `auth/me` → `settings.hl7_message_spec`) sets
    /// MSH-3 sending application and which custom Z-segment gets emitted.
    static var current: HL7Config {
        let format = AppStorageManager.shared.hl7MessageSpec
        return HL7Config(
            sendingApplication: format.rawValue,
            sendingFacility: AppStorageManager.shared.selectedTerminalName,
            receivingApplication: "PMS",
            receivingFacility: AppStorageManager.shared.pmsHostName,
            versionId: AppStorageManager.shared.hl7Version,
            format: format
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
        let transactionOrderId = txn.transaction_order_id ?? orderId

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
//                rxd.dispensingProviderFamilyName = user?.lname
//                rxd.dispensingProviderGivenName = user?.fname
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

            let imageObx = self.buildImageOBX(
                txn: txn,
                details: details,
                observationId: "DISP_IMG",
                label: "Dispense Image"
            )
            for obx in imageObx {
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

            for obx in self.buildDrugFlagOBX(drug: drug, startingSetId: imageObx.count + 1) {
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
                    builder.lotNumber = zsn.lotNumber
                    builder.expirationDate = zsn.expirationDate
                    builder.packageSerialNumber = zsn.packageSerialNumber
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

            // Custom Z-segment per HL7 spec dialect (server-driven via config.format).
            switch self.config.format {
            case .vivid:
                // No "Anonymous Mode" preference exists on iOS today — falls back
                // to "Anonymous" only when no user name is available.
                let vividUserName = user?.fname ?? "Anonymous"
                // Response only needs to identify the order — drug image/lot/serial/
                // expiration (optional fields) are dropped, not re-sent back to Vivid.
                scope.zui { zui in
                    zui.ndc = drug.ndc ?? ""
                    zui.vividUserName = vividUserName
                    zui.transactionOrderId = transactionOrderId
                    zui.rxNumber = orderId
                    zui.fillNumber = "1"
                    zui.dispensedQuantity = "\(totalCount)"
                    zui.transactionStatus = "CM"
                    zui.drugImage = nil
                    zui.drugLotNumber = nil
                    zui.drugSerialNumber = nil
                    zui.drugExpirationDate = nil
                }
            case .eyecon:
                scope.zni { zni in
                    zni.ndc = drug.ndc ?? ""
                    zni.drugName = drug.drug_name ?? ""
                    zni.userName = user?.fname ?? ""
                    zni.fillerOrderNumber = orderId
                    zni.dispenseAmount = "\(totalCount)"
                    zni.prescriptionNumber = orderId
                    zni.resultStatus = "F"
                    zni.stockBottleVerification = txn.is_ndc_verfied ? "A" : "N"
                }
            case .dispensesure:
                break
            }
        }

        let encoded = message.encode()

        switch config.format {
        case .eyecon:
            let verifiedByName = String((user?.fname ?? "").prefix(10))
            let fillStatus = "F"
            let ndcNoDash = (drug.ndc ?? "").replacingOccurrences(of: "-", with: "")

            var zuiFields = Array(repeating: "", count: 25)
            zuiFields[0] = ndcNoDash               // ZUI-1: NDC
            zuiFields[1] = drug.drug_name ?? ""    // ZUI-2: Drug Name
            zuiFields[2] = user?.fname ?? ""       // ZUI-3: Patient/User Name
            zuiFields[3] = orderId                  // ZUI-4: Prescription Number
            zuiFields[4] = "1"                      // ZUI-5: Fill Number
            zuiFields[5] = verifiedByName            // ZUI-6: Verified By
            zuiFields[6] = txn.is_ndc_verfied ? "A" : "N" // ZUI-7: Stock Bottle Verification
            zuiFields[7] = ""                       // ZUI-8: reserved
            zuiFields[8] = "1"                      // ZUI-9: Packet Version
            zuiFields[9] = user?.fname ?? ""       // ZUI-10: User/Tech Name
            zuiFields[10] = transactionOrderId        // ZUI-11: Transaction Order Id
            zuiFields[17] = "\(totalCount)"          // ZUI-18: Amount Actually Filled
            zuiFields[18] = fillStatus                // ZUI-19: Fill Status
            zuiFields[20] = ndcNoDash                 // ZUI-21: Stock Bottle Barcode NDC
            let zuiSegment = "ZUI|" + zuiFields.joined(separator: "|")

            return insertSegment(zuiSegment, afterMSHIn: encoded)
        default:
            return encoded
        }
    }

    /// Inserts `segment` immediately after the MSH segment in an already-encoded
    /// HL7 message (segments CR-separated). Used for segments not modeled by the
    /// Hl7Core builder (e.g. the Eyecon-specific ZUI field layout).
    private func insertSegment(_ segment: String, afterMSHIn encoded: String) -> String {
        var segments = encoded.components(separatedBy: "\r")
        guard let mshIndex = segments.firstIndex(where: { $0.hasPrefix("MSH") }) else {
            return encoded
        }
        segments.insert(segment, at: mshIndex + 1)
        return segments.joined(separator: "\r")
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
//                    inv.setId = "\(index)"
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
        var imgCounter = 1
        func nextImgId() -> String {
            defer { imgCounter += 1 }
            return "IMG" + String(format: "%03d", imgCounter)
        }

        for (index, detail) in details.enumerated() {

            let count = detail.pill_count
            let type = (detail.type ?? "UNKNOWN").toImageLabel

            let fileName: String
            if let path = detail.image_path {
                fileName = (path as NSString).lastPathComponent
            } else {
                fileName = ""
            }

            // let observationValue = "count=\(count)|type=\(type)|image=\(fileName)"
            let observationValue = detail.image_path.map { "/images/\($0)" } ?? ""

            obxList.append(
                ObxRow(
                    setId: "\(index + 1)",
                    // valueType: "ST",
                    valueType: "RP",
                    // observationId: observationId,
                    observationId: nextImgId(),
                    // observationText: "\(label) \(index + 1)",
                    observationText: type,
                    observationValue: observationValue,
                    resultStatus: "F",
                    units: nil
                )
            )
            _ = count; _ = fileName
        }

        // Barcode Image — one row per scanned bottle that has a captured image.
        let bottleBarcodePaths = [BottleInfo].decode(from: txn.bottle_info_list_json)
            .compactMap { $0.barcodeImagePath }
            .filter { !$0.isEmpty }

        for barcodePath in bottleBarcodePaths {
            let fileName = (barcodePath as NSString).lastPathComponent

            obxList.append(
                ObxRow(
                    setId: "\(obxList.count + 1)",
                    // valueType: "ST",
                    valueType: "RP",
                    // observationId: observationId,
                    observationId: nextImgId(),
                    observationText: "Barcode Image",
                    // observationValue: "count=0|type=\(ControlledStep.scan.imageLabel)|image=\(fileName)",
                    observationValue: "/images/\(barcodePath)",
                    resultStatus: "F",
                    units: nil
                )
            )
            _ = fileName
        }

        return obxList
    }

    // MARK: Controlled/Hazardous OBX Builder

    /// Controlled = `drug.drug_type` set (DEA schedule string, e.g. "II"); Hazardous
    /// = `drug.is_hazardous`. Two CE-typed OBX rows after the image OBX segments,
    /// per PMS spec: OBX-3 identifier^text^L, OBX-5 Y/N^Yes/No^HL70136.
    func buildDrugFlagOBX(drug: DrugMasterEntity, startingSetId: Int) -> [ObxRow] {
        let isControlled = !(drug.drug_type ?? "").isEmpty

        return [
            ObxRow(
                setId: "\(startingSetId)",
                valueType: "CE",
                observationId: "CONTROLLED_SUBSTANCE^Controlled Substance^L",
                observationText: nil,
                observationValue: isControlled ? "Y^Yes^HL70136" : "N^No^HL70136",
                resultStatus: "F",
                units: nil
            ),
            ObxRow(
                setId: "\(startingSetId + 1)",
                valueType: "CE",
                observationId: "HAZARDOUS_DRUG^Hazardous Drug^L",
                observationText: nil,
                observationValue: drug.is_hazardous ? "Y^Yes^HL70136" : "N^No^HL70136",
                resultStatus: "F",
                units: nil
            )
        ]
    }

    // MARK: ZSN/ZSV Builders

    struct ZsnRow {
        let setId: String
        let nationalDrugCode: String?
        let quantityFromThisStockItem: String
        let captureSource: String
        let captureTimestamp: String
        let transactionType: String
        let lotNumber: String?
        let expirationDate: String?
        let packageSerialNumber: String?
    }

    /// One ZSN row per physical bottle scanned during the transaction, each with its
    /// own live-computed pill count (never cached — see `BottleInfo`). Falls back to
    /// the legacy one-row-per-detail behavior for transactions with no bottle list
    /// (predates multi-bottle tracking, or a scan path that never populated one).
    func buildZSN(
        txn: PillCountTransactionEntity,
        details: [PillCountTransactionDetailsEntity],
        drug: DrugMasterEntity,
        now: String
    ) -> [ZsnRow] {
        let bottles = TransactionStore.shared.getBottleList(txnId: txn.txn_id)

        guard !bottles.isEmpty else {
            return details.enumerated().map { index, detail in
                ZsnRow(
                    setId: "\(index + 1)",
                    nationalDrugCode: drug.ndc,
                    quantityFromThisStockItem: "\(detail.pill_count)",
                    captureSource: detail.is_manual ? ScanSource.shared.MANUAL : ScanSource.shared.UNKNOWN,
                    captureTimestamp: now,
                    transactionType: ZsnTransactionType.shared.DISPENSE,
                    lotNumber: nil,
                    expirationDate: nil,
                    packageSerialNumber: nil
                )
            }
        }

        let detailIdSet = Set(details.map { $0.txn_details_id })
        let anyManual = details.contains { $0.is_manual }

        return bottles.enumerated().map { index, bottle in
            let ownedIds = bottle.txnDetailsIds.filter { detailIdSet.contains($0) }
            let quantity = TransactionDetailStore.shared.sumPillCount(detailIds: ownedIds)
            return ZsnRow(
                setId: "\(index + 1)",
                nationalDrugCode: drug.ndc,
                quantityFromThisStockItem: "\(quantity)",
                captureSource: anyManual ? ScanSource.shared.MANUAL : ScanSource.shared.UNKNOWN,
                captureTimestamp: now,
                transactionType: ZsnTransactionType.shared.DISPENSE,
                lotNumber: bottle.lotNumber,
                expirationDate: bottle.expirationDate,
                packageSerialNumber: bottle.serialNumber
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

    private func validatorName(for txn: PillCountTransactionEntity) -> String {
        guard let user = txn.user else { return "PillCounter" }
        let name = [user.fname, user.lname]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "PillCounter" : name
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
            validator: validatorName(for: txn),
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

        let status = txn.status ?? CountStatus.COMPLETED.rawValue
        var comment = "Transaction Id: \(txn.txn_id) | Status: \(status) | Total Count: \(totalCount)"

        let expected = Int(txn.target_count)
        if expected != totalCount {
            let diff = totalCount - expected
            comment += " | Count Mismatch: Expected \(expected), Counted \(totalCount), Diff \(diff)"
        }

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
