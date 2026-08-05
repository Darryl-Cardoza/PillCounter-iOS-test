//
//  HL7ACKBuilder.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/04/26.
//
import Hl7Core
import Foundation


/// Handles building HL7 ACK/NACK responses based on incoming message, via
/// Hl7Core's `ack { }` DSL (same builder library used by `HL7CompletionBuilder`)
/// rather than hand-rolled strings.
enum HL7ACKBuilder {

    enum AckCode: String {
        case AA // Application Accept
        case AE // Application Error
        case AR // Application Reject
    }

    /// Builds ACK/NACK response from raw HL7 message.
    static func buildResponse(
        from message: String,
        code: AckCode,
        errorMessage: String? = nil
    ) -> String {

        let lines = message
            .components(separatedBy: CharacterSet.newlines)
            .filter { !$0.isEmpty }

        // Try extracting MSH
        guard let mshLine = lines.first(where: { $0.hasPrefix("MSH") }) else {
            return buildFallbackACK(code: .AR, error: "Missing MSH")
        }

        let fields = mshLine.components(separatedBy: "|")

        // Receiving side of the ACK = whoever sent the inbound message (MSH-3/4).
        let inboundSendingApp = fields[safe: 2] ?? "UNKNOWN"
        let inboundSendingFacility = fields[safe: 3] ?? "UNKNOWN"
        let messageControlId = fields[safe: 9] ?? "UNKNOWN"

        return build(
            receivingApplication: inboundSendingApp,
            receivingFacility: inboundSendingFacility,
            messageControlId: messageControlId,
            code: code,
            errorMessage: errorMessage
        )
    }

    // MARK: - Fallback ACK (invalid HL7)

    /// Builds fallback ACK when message is completely invalid.
    private static func buildFallbackACK(code: AckCode, error: String) -> String {
        return build(
            receivingApplication: "UNKNOWN",
            receivingFacility: "UNKNOWN",
            messageControlId: "UNKNOWN",
            code: code,
            errorMessage: error
        )
    }

    /// Shared ACK^R01 construction via `Hl7Core`. MSH-3/4 (sender) are this
    /// app's identity from `HL7Config` — terminal name / configured HL7 format —
    /// matching what `HL7CompletionBuilder` sends elsewhere. MSH-5/6 (receiver)
    /// echo back the inbound sender so the ACK routes to whoever sent it.
    private static func build(
        receivingApplication: String,
        receivingFacility: String,
        messageControlId: String,
        code: AckCode,
        errorMessage: String?
    ) -> String {
        let config = HL7Config.current
        let builder = HL7Builder.companion.builder()
            .defaultVersion(version: config.versionId)
            .build()

        let message = builder.ack { scope in
            scope.msh { msh in
                msh.sendingApplication = config.sendingApplication
                msh.sendingFacility = config.sendingFacility
                msh.receivingApplication = receivingApplication
                msh.receivingFacility = receivingFacility
                msh.dateTimeOfMessage = DateUtils.currentTimestamp()
                msh.messageControlId = UUID().uuidString
                msh.processingId = "P"
                msh.versionId = config.versionId
            }

            scope.msa { msa in
                msa.acknowledgmentCode = code.rawValue
                msa.messageControlId = messageControlId
            }

            if let errorMessage, code != .AA {
                scope.err { err in
                    err.errorText = errorMessage
                }
            }
        }

        return message.encode()
    }
}


extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum ValidationResult {
    case valid
    case invalid(String)      // → AR
    case unsupported(String)  // → AR
}

struct HL7Validator {

    static func validate(_ message: String) -> ValidationResult {

        // Split segments safely — real devices (Vivid) send \n instead of \r
        let segments = message
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // MARK: - 1. MSH validation
        guard let msh = segments.first(where: { $0.hasPrefix("MSH|") }) else {
            return .invalid("Missing MSH segment")
        }

        let fields = msh.components(separatedBy: "|")

        // MARK: - 2. Message Control ID (MSH-10)
//        guard let controlId = fields[safe: 9],
//              !controlId.trimmingCharacters(in: .whitespaces).isEmpty else {
//            return .invalid("Missing Message Control ID (MSH-10)")
//        }

        // MARK: - 3. Message Type (MSH-9)
        guard let typeField = fields[safe: 8] else {
            return .invalid("Missing message type (MSH-9)")
        }

        let components = typeField.components(separatedBy: "^")
        guard components.count >= 2 else {
            return .invalid("Invalid message type format")
        }

        let messageType = components[0]
        let trigger = components[1]

        // MARK: - 4. Supported Types
        switch (messageType, trigger) {

        // =========================
        // DISPENSE → RDE^O11 (Vivid) / RDE^O01 (Eyecon)
        // =========================
        case ("RDE", "O11"), ("RDE", "O01"):

            let hasZUI = segments.contains { $0.hasPrefix("ZUI|") }
            let hasZNI = segments.contains { $0.hasPrefix("ZNI|") }

            // Vivid → ZUI present, other segments optional
            if hasZUI {
                return .valid
            }

            // Eyecon → ZNI present, other segments optional
            if hasZNI {
                return .valid
            }

            // Neither ZUI nor ZNI present → fall back to ORC/RXE mandatory check
            let hasORC = segments.contains { $0.hasPrefix("ORC|") }
            if !hasORC {
                return .invalid("Missing ORC segment")
            }

            let rxeSegments = segments.filter { $0.hasPrefix("RXE|") }
            if rxeSegments.isEmpty {
                return .invalid("Missing RXE segment")
            }

            for (index, rxe) in rxeSegments.enumerated() {

                let fields = rxe.components(separatedBy: "|")

                let ndc = fields[safe: 2]?.trimmingCharacters(in: .whitespaces) ?? ""
                if ndc.isEmpty {
                    return .invalid("Missing NDC in RXE \(index + 1)")
                }

                let qty = fields[safe: 3]?.trimmingCharacters(in: .whitespaces) ?? ""
                if qty.isEmpty {
                    return .invalid("Missing quantity in RXE \(index + 1)")
                }
            }

            return .valid

        // =========================
        // INVENTORY → INR^U04
        // =========================
        case ("INR", "U04"):

            // Prefer OBX
            let obxSegments = segments.filter { $0.hasPrefix("OBX|") }

            if !obxSegments.isEmpty {
                for (index, obx) in obxSegments.enumerated() {
                    let fields = obx.components(separatedBy: "|")

                    // OBX-5 → NDC / value
                    let value = fields[safe: 5]?.trimmingCharacters(in: .whitespaces) ?? ""
                    if value.isEmpty {
                        return .invalid("Missing value in OBX \(index + 1)")
                    }
                }

                return .valid
            }

            // Fallback: allow RXE (non-standard PMS)
            let rxeSegments = segments.filter { $0.hasPrefix("RXE|") }

            if !rxeSegments.isEmpty {
                for (index, rxe) in rxeSegments.enumerated() {
                    let fields = rxe.components(separatedBy: "|")

                    let ndc = fields[safe: 2]?.trimmingCharacters(in: .whitespaces) ?? ""
                    if ndc.isEmpty {
                        return .invalid("Missing NDC in RXE \(index + 1)")
                    }
                }

                return .valid
            }

            return .invalid("Missing OBX/RXE segment for INR^U04")

        // =========================
        // Unsupported
        // =========================
        default:
            return .unsupported("Unsupported message type \(messageType)^\(trigger)")
        }
    }
}
