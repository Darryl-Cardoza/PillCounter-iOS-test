//
//  HL7CompletionBuilder.swift
//  PillCounter
//

import Hl7Core
import UIKit
import Darwin
import CoreData

struct HL7Config {
    let sendingApplication: String
    let sendingFacility: String
    let receivingApplication: String
    let receivingFacility: String
    let versionId: String
    let format: Hl7Format

    /// Sourced from `AppStorageManager`: the terminal name identifies this
    /// station as the sending facility. The receiving facility is the live
    /// resolved PMS service name (set on connect — see
    /// `Hl7ServiceManager.handleClientStateChange`), falling back to the
    /// configured PMS host name if not yet connected.
    /// `format` (server-driven, `auth/me` → `settings.hl7_message_spec`) sets
    /// MSH-3 sending application and which custom Z-segment gets emitted.
    static var current: HL7Config {
        let format = AppStorageManager.shared.hl7MessageSpec
        return HL7Config(
            sendingApplication: format.rawValue,
            sendingFacility: AppStorageManager.shared.selectedTerminalName,
            receivingApplication: "PMS",
            receivingFacility: AppStorageManager.shared.resolvedPMSServiceName ?? AppStorageManager.shared.pmsHostName,
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

    /// Every Core Data touch this builder makes (directly, and via the
    /// TransactionStore/TransactionDetailStore/StockTxnStore/BottleInfoStore
    /// calls it fans out to) uses this context, not the stores' own default
    /// `viewContext`. Defaults to `viewContext` so every existing call site
    /// (main-thread `Hl7ServiceController` paths) is unchanged; HL7 sync
    /// queue callers pass an explicit background context instead, so the
    /// whole message-build graph — including `txn`/`batch`'s own relationship
    /// faults — stays on one background queue for the call's duration rather
    /// than hopping back to `viewContext` mid-build.
    private let context: NSManagedObjectContext

    /// `config` defaults to values sourced from `AppStorageManager` (terminal
    /// name, PMS host name, HL7 version — the latter from `auth/me` →
    /// `settings.hl7_version`), so built messages always match what the
    /// connected PMS expects.
    init(config: HL7Config = .current, context: NSManagedObjectContext = CoreDataManager.shared.context) {
        self.config = config
        self.context = context
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
        let totalCount = dispensedCount(txn: txn, details: details)

        guard let drug = txn.drug else {
            fatalError("Drug missing")
        }

        let orderId = txn.rx_no ?? "\(txn.txn_id)"
        let transactionOrderId = txn.transaction_order_id ?? orderId

        let imageObx = self.buildImageOBX(
            txn: txn,
            details: details,
            observationId: "DISP_IMG",
            label: "Dispense Image"
        )

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
                rxd.dispensingProviderFamilyName = user?.lname
                rxd.dispensingProviderGivenName = user?.fname
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
                    // Placeholder — real value is spliced in as raw text below because
                    // `^`/`&` inside this string would otherwise come back HL7-escaped
                    // (see buildZuiDrugImageField doc).
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

        var encoded = message.encode()

        let drugFlagObx = self.buildDrugFlagOBX(drug: drug, startingSetId: imageObx.count + 1)
        encoded = insertSegments(
            drugFlagObx.map { self.rawObxSegment($0) },
            afterLastPrefixIn: encoded,
            prefix: "OBX"
        )

        if config.format == .vivid {
            let zuiImageField = self.buildZuiDrugImageField(txn: txn, details: details)
            encoded = self.setZuiField8(zuiImageField, in: encoded)
            // Hl7Core's `scope.zui { }` DSL call appends ZUI wherever it was invoked in
            // the builder block (after ZSV) — per Vivid spec, ZUI must sit immediately
            // after MSH. Move it here rather than reordering the DSL call, since ORC/
            // PID/RXD must still precede ZSN/ZSV per the RDS^O13 structure.
            encoded = self.moveZuiAfterMSH(in: encoded)
        }

        let finalMessage: String
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

            finalMessage = insertSegment(zuiSegment, afterMSHIn: encoded)
        default:
            finalMessage = encoded
        }

        guard self.validateHl7Message(finalMessage) else {
            Log("HL7: buildCompletionMessage validation failed — refusing to send")
            return ""
        }

        return finalMessage
    }

    /// Relocates the ZUI segment (wherever the DSL placed it) to immediately after
    /// MSH, per Vivid spec. No-op if no ZUI segment is present.
    private func moveZuiAfterMSH(in encoded: String) -> String {
        var segments = encoded.components(separatedBy: "\r")
        guard let zuiIndex = segments.firstIndex(where: { $0.hasPrefix("ZUI") }),
              let mshIndex = segments.firstIndex(where: { $0.hasPrefix("MSH") }) else {
            return encoded
        }
        let zuiSegment = segments.remove(at: zuiIndex)
        let insertAt = zuiIndex < mshIndex ? mshIndex : mshIndex + 1
        segments.insert(zuiSegment, at: insertAt)
        return segments.joined(separator: "\r")
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

    /// Inserts `segments` after the last segment whose tag starts with `prefix`
    /// (falls back to end of message if none found). Used to raw-append the
    /// Controlled/Hazardous OBX rows: the Hl7Core `OBXBuilder` writes
    /// `observationId`/`observationValue` into a single unescaped subcomponent,
    /// so any `^` passed through it comes back HL7-escaped as `\S\` instead of
    /// staying a literal component separator. Building these two rows as raw
    /// pipe-delimited text sidesteps that until the builder gains component-level
    /// setters for OBX-3.2/3.3 and OBX-5.2/5.3.
    private func insertSegments(_ newSegments: [String], afterLastPrefixIn encoded: String, prefix: String) -> String {
        var segments = encoded.components(separatedBy: "\r")
        let insertAt = segments.lastIndex(where: { $0.hasPrefix(prefix) }).map { $0 + 1 } ?? segments.count
        segments.insert(contentsOf: newSegments, at: insertAt)
        return segments.joined(separator: "\r")
    }

    /// Builds ZUI-8 (drugImage): one `^`-separated repetition per image sent in
    /// the completion message — every tray photo plus every scanned-bottle
    /// barcode image, matching the full image set reported via OBX
    /// (`buildImageOBX`) rather than tray photos alone. Each repetition is
    /// `<batch>&<count>&<base64>` where batch/count are 1-based labels of the
    /// form `1B{batch}` / `1C{count}` per the Vivid spec. This app's
    /// `PillCountTransactionDetailsEntity` has no batch/count number of its own
    /// (batching is a separate INR flow), so every image is reported as batch 1,
    /// with the count number set to its 1-based position across the combined list.
    private func buildZuiDrugImageField(
        txn: PillCountTransactionEntity,
        details: [PillCountTransactionDetailsEntity]
    ) -> String {
        // `image_path`/`barcodeImagePath` store only the filename of an AES-GCM
        // encrypted file under Documents/ (see PhotoFileManager.saveImage) —
        // decrypt before base64 encoding, or the PMS receives ciphertext instead
        // of a JPEG.
        let detailImages: [String] = details.compactMap { $0.image_path }
        let barcodeImages: [String] = [BottleInfo].decode(from: txn.bottle_info_list_json)
            .compactMap { $0.barcodeImagePath }
            .filter { !$0.isEmpty }

        let repetitions: [String] = (detailImages + barcodeImages).enumerated().compactMap { index, fileName in
            guard let data = PhotoFileManager.shared.loadDecryptedData(from: fileName) else { return nil }
            return "1B1&1C\(index + 1)&\(data.base64EncodedString())"
        }
        return repetitions.joined(separator: "^")
    }

    /// Sets ZUI field 8 (drugImage) to raw, unescaped `value` in an already-encoded
    /// message. The Hl7Core `ZUIDispenseBuilder` writes field 8 through a single
    /// escaped subcomponent, so the `^`/`&` structure required by the multi-image
    /// packing above would come back HL7-escaped if set via the DSL — same class
    /// of issue as the Controlled/Hazardous OBX rows (see `rawObxSegment`).
    private func setZuiField8(_ value: String, in encoded: String) -> String {
        var segments = encoded.components(separatedBy: "\r")
        guard let zuiIndex = segments.firstIndex(where: { $0.hasPrefix("ZUI") }) else {
            return encoded
        }
        var fields = segments[zuiIndex].components(separatedBy: "|")
        while fields.count <= 8 { fields.append("") }
        fields[8] = value
        segments[zuiIndex] = fields.joined(separator: "|")
        return segments.joined(separator: "\r")
    }

    /// Guards against sending a malformed message: MSH-12 (version id) and the
    /// other MSH required fields must be non-empty. An HL7 message with a blank
    /// version or missing required MSH fields must never reach the PMS.
    private func validateHl7Message(_ encoded: String) -> Bool {
        let segments = encoded.components(separatedBy: "\r")
        guard let msh = segments.first(where: { $0.hasPrefix("MSH") }) else {
            Log("HL7 validation: no MSH segment")
            return false
        }

        let fields = msh.components(separatedBy: "|")
        // fields[0] == "MSH", fields[1] = encoding characters (MSH-2).
        // fields[6] = MSH-7 dateTimeOfMessage, [8] = MSH-9 messageType,
        // [9] = MSH-10 messageControlId, [10] = MSH-11 processingId,
        // [11] = MSH-12 versionId. Sending/receiving app+facility (MSH-3..6)
        // are legitimately blank under static-IP PMS connection mode (no
        // terminal name / PMS host name configured), so not required here.
        let requiredMshFieldIndexes = [6, 8, 9, 10, 11]
        for index in requiredMshFieldIndexes {
            guard index < fields.count, !fields[index].trimmingCharacters(in: .whitespaces).isEmpty else {
                Log("HL7 validation: MSH field \(index) is empty")
                return false
            }
        }

        guard !self.versionId.trimmingCharacters(in: .whitespaces).isEmpty else {
            Log("HL7 validation: version id is empty")
            return false
        }

        return true
    }

    /// Raw OBX-8 field layout matching the PMS spec exactly:
    /// `OBX|set|CE|ID^Text^L||Value^ValueText^HL70136||||||F`
    private func rawObxSegment(_ obx: ObxRow) -> String {
        let observationId = obx.observationId // e.g. "CONTROLLED_SUBSTANCE^Controlled Substance^L"
        var fields = Array(repeating: "", count: 11)
        fields[0] = obx.setId
        fields[1] = obx.valueType
        fields[2] = observationId
        fields[4] = obx.observationValue
        fields[10] = obx.resultStatus
        return "OBX|" + fields.joined(separator: "|")
    }

    // MARK: - Inventory Response (INU^U05 — standard segments plus one Z-segment, ZAD)
    //
    // Built entirely through Hl7Core's `InuU05Scope` DSL — `invCount` for each
    // INV row (the library's standard-first count-result layout: itemCode/
    // statusCode/typeCode/quantityOnHand/../lotNumber map straight onto
    // INV-1/2/3/7/8/9/16 per the official HL7 spec), `zad` for the batch's
    // adjustment note (this app's only structured note today), and `obx` for the
    // operator-identification and per-INV SEALED_QTY/OPEN_QTY rows (OBX-4 subId
    // links each pair back to its INV's setId).
    //
    // No serial number / GTIN sent (not tracked by BottleInfoEntity/DrugMasterEntity
    // today — grouping stays keyed on ndc+name+lot+expiry, same as before).
    // Image OBX rows (IMG001, IMG002... — same scheme as dispense's buildImageOBX)
    // are emitted per-INV, one per captured image, only when a group's opened rows
    // carried images (controlled-drug open-pill counts) — see BottleInfoEntity.images.
    // ZAD carries batch.note as a free-text adjustment
    // comment when present — no structured adjustment type/reason/quantity exists
    // anywhere in this app's data model today. Groups with total qty 0 are skipped
    // entirely (spec §9 Scenarios 1-4 — every response is a plain count).
    func buildInventoryMessage(
        batch: BatchCountEntity,
        user: UserEntity?
    ) -> String {

        let now = DateUtils.currentTimestamp()
        let messageId = "RES\(Int(Date().timeIntervalSince1970))"
        let requestId = batch.req_id_from_pms ?? "REQ\(batch.batch_id)"

        let stockTxns = StockTxnStore.shared.fetchByBatch(batchId: batch.batch_id, in: context)

        // MARK: GROUPING
        struct Key: Hashable {
            let ndc: String; let name: String; let lot: String; let expiry: String
        }
        var grouped: [Key: (opened: Int32, sealed: Int32, images: [BottleImageRecord])] = [:]

        for stockTxn in stockTxns {
            guard let drug = stockTxn.drug else { continue }
            let bottles = BottleInfoStore.shared.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id, in: context)
            for bottle in bottles {
                let key = Key(
                    ndc: drug.ndc ?? "", name: drug.drug_name ?? "",
                    lot: bottle.lot_no ?? "", expiry: bottle.exp_no ?? ""
                )
                var e = grouped[key] ?? (0, 0, [])
                // Use the same isSealed discriminator as the rest of the app
                // (BottleInfoStore.fetchSealedRow, StockCountViewModel, HistoryViewModel)
                // rather than loose_qty == 0 alone — addOpenedBottle sets bottle_qty=0
                // on opened rows, so a bottle opened and counted to 0 loose pills is
                // still correctly seen as opened, not sealed.
                if bottle.isSealed {
                    e.sealed += bottle.bottle_qty * drug.package_qty
                } else {
                    e.opened += bottle.loose_qty
                    e.images += bottle.images
                }
                grouped[key] = e
            }
        }

        // Zero-total groups carry no information for PMS — never emit an INV for them.
        grouped = grouped.filter { $0.value.opened + $0.value.sealed > 0 }

        var setId = 1

        // Message-level OBX row (OBX-4 blank) — operator identification. Name is
        // Same OperatorName.current UnifiedCameraView uses for captured-image overlays.
        // OPERATOR_ID intentionally omitted.
        let operatorName = OperatorName.current(fname: user?.fname, lname: user?.lname)

        let message = builder.inuU05 { scope in
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
                // ORC-2: this batch's own id, correlated to the inbound request's
                // MSH-10 when this response is answering one (spec §3).
                orc.placerOrderNumber = "\(batch.batch_id)^\(requestId)"
            }

            // batch.note doubles as this app's only adjustment note today — no
            // structured adjustment type/reason/quantity is captured anywhere, so
            // ZAD only carries the free-text comment + who's responsible for it.
            let adjustmentNote = batch.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !adjustmentNote.isEmpty {
                scope.zad { zad in
                    zad.setId = "1"
                    zad.comment = adjustmentNote
                    zad.approvedBy = operatorName
                }
            }

            scope.obx { obx in
                obx.setId = "\(setId)"
                obx.valueType = "ST"
                obx.observationId = "OPERATOR_NAME"
                obx.observationValue = operatorName
                obx.resultStatus = "F"
            }
            setId += 1

            // One INV per group, immediately followed by its SEALED_QTY/OPEN_QTY OBX rows.
            var invSetId = 1
            var imgIdCounter = ImgIdCounter()
            for (key, value) in grouped {
                let total = value.opened + value.sealed

                scope.invCount { inv in
                    inv.setId = "\(invSetId)"
                    inv.itemCode = key.ndc                             // INV-1 Substance Identifier
                    inv.itemName = key.name
                    inv.codingSystem = "L"
                    inv.statusCode = "A"                               // INV-2 Substance Status
                    inv.statusTable = "HL70383"
                    inv.statusText = "Active"
                    inv.typeCode = "DRUG"                              // INV-3 Substance Type
                    inv.typeTable = "HL70384"
                    inv.typeText = "Drug"
                    inv.quantityOnHand = "\(total)"                    // INV-7
                    inv.quantityAvailable = "\(total)"                 // INV-8
                    inv.quantityExpected = "\(total)"                  // INV-9
                    inv.unitsCode = "TAB"                              // INV-11
                    inv.unitsText = "Tablets"
                    inv.unitsCodeSystem = "UCUM"
                    inv.expirationDate = key.expiry                    // INV-12
                    inv.lotNumber = key.lot                            // INV-16
                }

                scope.obx { obx in
                    obx.setId = "\(setId)"
                    obx.valueType = "NM"
                    obx.observationId = "SEALED_QTY"
                    obx.subId = "\(invSetId)"
                    obx.observationValue = "\(value.sealed)"
                    obx.resultStatus = "F"
                }
                setId += 1

                scope.obx { obx in
                    obx.setId = "\(setId)"
                    obx.valueType = "NM"
                    obx.observationId = "OPEN_QTY"
                    obx.subId = "\(invSetId)"
                    obx.observationValue = "\(value.opened)"
                    obx.resultStatus = "F"
                }
                setId += 1

                // One OBX per image, same shape as the dispense flow's buildImageOBX —
                // unique observationId (IMG001, IMG002...) rather than `~`-joining paths
                // into one field (`~` is HL7's repeat separator; Hl7Core's encoder escapes
                // a literal `~` in a value to `\R\`). subId still links back to this INV,
                // which dispense's single-drug messages never needed.
                for image in value.images {
                    scope.obx { obx in
                        obx.setId = "\(setId)"
                        obx.valueType = "RP"
                        obx.observationId = imgIdCounter.next()
                        obx.subId = "\(invSetId)"
                        obx.observationValue = "/images/\(image.path)"
                        obx.resultStatus = "F"
                    }
                    setId += 1
                }

                invSetId += 1
            }
        }

        return message.encode()
    }
}

// MARK: - Shared Private Helpers
private extension HL7CompletionBuilder {

    // MARK: Image observationId counter
    // IMG001, IMG002... — one instance per message build, never shared across builds,
    // so each message's image OBX rows get their own contiguous IMG### sequence.
    struct ImgIdCounter {
        private var counter = 1
        mutating func next() -> String {
            defer { counter += 1 }
            return "IMG" + String(format: "%03d", counter)
        }
    }

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
        var imgIdCounter = ImgIdCounter()

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
//            let observationValue = fileName

            obxList.append(
                ObxRow(
                    setId: "\(index + 1)",
                    // valueType: "ST",
                    valueType: "RP",
                    // observationId: observationId,
                    observationId: imgIdCounter.next(),
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
                    observationId: imgIdCounter.next(),
                    observationText: "Barcode Image",
                    // observationValue: "count=0|type=\(ControlledStep.scan.imageLabel)|image=\(fileName)",
                    // observationValue: "/images/\(barcodePath)",
                    observationValue: fileName,
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
        let bottles = TransactionStore.shared.getBottleList(txnId: txn.txn_id, in: context)

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
            let quantity = TransactionDetailStore.shared.sumPillCount(detailIds: ownedIds, in: context)
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

    // MARK: Detail Extractor

    func pillCountDetails(
        from txn: PillCountTransactionEntity
    ) -> [PillCountTransactionDetailsEntity] {
        return (txn.pillCountTransactionDetails as? Set<PillCountTransactionDetailsEntity>)
            .map { Array($0) } ?? []
    }

    /// Actual dispensed amount for the completion message. The controlled
    /// workflow (`.containerInitiate`, `.vial`, `.containerPending`, ...)
    /// writes a detail row per step, so summing every row in `details`
    /// double/triple-counts the same pills across steps. `.targetVerification`
    /// is the step whose count represents what was actually dispensed — use
    /// it when present, falling back to the full sum for the simple flows
    /// that only ever write one step's rows.
    private func dispensedCount(
        txn: PillCountTransactionEntity,
        details: [PillCountTransactionDetailsEntity]
    ) -> Int {
        let verificationRows = details.filter { $0.type == ControlledStep.targetVerification.rawValue }
        guard !verificationRows.isEmpty else {
            return details.map { Int($0.pill_count) }.reduce(0, +)
        }
        return verificationRows.map { Int($0.pill_count) }.reduce(0, +)
    }
}
