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
