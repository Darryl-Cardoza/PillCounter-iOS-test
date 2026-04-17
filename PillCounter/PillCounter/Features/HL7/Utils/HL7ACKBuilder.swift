//
//  HL7ACKBuilder.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/04/26.
//
import Foundation


/// Handles building HL7 ACK/NACK responses based on incoming message.
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

        // Extract required fields safely
        let sendingApp = fields[safe: 2] ?? "UNKNOWN"
        let sendingFacility = fields[safe: 3] ?? "UNKNOWN"
        let _receivingApp = fields[safe: 4] ?? "UNKNOWN"
        let _receivingFacility = fields[safe: 5] ?? "UNKNOWN"
        let messageControlId = fields[safe: 9] ?? "UNKNOWN"

        let ackMessageId = UUID().uuidString

        var ack = ""

        // MARK: - MSH
        ack += "MSH|^~\\&|PillCounter|ROBOT|\(sendingApp)|\(sendingFacility)|\(DateUtils.currentTimestamp())||ACK^R01|\(ackMessageId)|P|2.5\n"

        // MARK: - MSA
        ack += "MSA|\(code.rawValue)|\(messageControlId)"

        // MARK: - Error segment (optional)
        if let errorMessage, code != .AA {
            ack += "\nERR|||0^ERROR|\(errorMessage)"
        }

        return ack
    }

    // MARK: - Fallback ACK (invalid HL7)

    /// Builds fallback ACK when message is completely invalid.
    private static func buildFallbackACK(code: AckCode, error: String) -> String {
        return """
        MSH|^~\\&|PillCounter|ROBOT|UNKNOWN|UNKNOWN|\(DateUtils.currentTimestamp())||ACK^R01|\(UUID().uuidString)|P|2.5
        MSA|\(code.rawValue)|UNKNOWN
        ERR|||0^ERROR|\(error)
        """
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

        // Split segments safely
        let segments = message
            .components(separatedBy: "\r")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // MARK: - 1. MSH validation
        guard let msh = segments.first(where: { $0.hasPrefix("MSH|") }) else {
            return .invalid("Missing MSH segment")
        }

        let fields = msh.components(separatedBy: "|")

        // MARK: - 2. Message Control ID (MSH-10)
        guard let controlId = fields[safe: 9],
              !controlId.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .invalid("Missing Message Control ID (MSH-10)")
        }

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
        // DISPENSE → RDE^O11
        // =========================
        case ("RDE", "O11"):

            // Must have ORC
            let hasORC = segments.contains { $0.hasPrefix("ORC|") }
            if !hasORC {
                return .invalid("Missing ORC segment")
            }

            // Must have RXE
            let rxeSegments = segments.filter { $0.hasPrefix("RXE|") }
            if rxeSegments.isEmpty {
                return .invalid("Missing RXE segment")
            }

            // Validate each RXE (basic only)
            for (index, rxe) in rxeSegments.enumerated() {

                let fields = rxe.components(separatedBy: "|")

                // RXE-2 → NDC
                let ndc = fields[safe: 2]?.trimmingCharacters(in: .whitespaces) ?? ""
                if ndc.isEmpty {
                    return .invalid("Missing NDC in RXE \(index + 1)")
                }

                // RXE-3 → Qty
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
            
            return .valid

            // Prefer OBX
//            let obxSegments = segments.filter { $0.hasPrefix("OBX|") }
//
//            if !obxSegments.isEmpty {
//                for (index, obx) in obxSegments.enumerated() {
//
//                    let fields = obx.components(separatedBy: "|")
//
//                    // OBX-5 → NDC / value
//                    let value = fields[safe: 5]?.trimmingCharacters(in: .whitespaces) ?? ""
//                    if value.isEmpty {
//                        return .invalid("Missing value in OBX \(index + 1)")
//                    }
//                }
//
//                return .valid
//            }

            // Fallback: allow RXE (non-standard PMS)
//            let rxeSegments = segments.filter { $0.hasPrefix("RXE|") }
//
//            if !rxeSegments.isEmpty {
//                for (index, rxe) in rxeSegments.enumerated() {
//
//                    let fields = rxe.components(separatedBy: "|")
//
//                    let ndc = fields[safe: 2]?.trimmingCharacters(in: .whitespaces) ?? ""
//                    if ndc.isEmpty {
//                        return .invalid("Missing NDC in RXE \(index + 1)")
//                    }
//                }
//
//                return .valid
//            }
//
//            return .invalid("Missing OBX/RXE segment for INR^U04")

        // =========================
        // Unsupported
        // =========================
        default:
            return .unsupported("Unsupported message type \(messageType)^\(trigger)")
        }
    }
}
