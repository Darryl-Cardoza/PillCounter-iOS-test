//
//  HL7ACKBuilder.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/04/26.
//
import Hl7Core
import Foundation


/// Fallback ACK construction for the one case Hl7Core's `AckBuilder` can't
/// handle: a message so malformed it produced no parseable MSH at all (no
/// `HL7Message`, not even a `partialMessage`, to swap sender/receiver from).
/// Every other ACK/NACK — including all validation rejects — goes through
/// Hl7Core's `AckBuilder.build(inbound:result:)` directly (see
/// `Hl7ServiceManager.startServerIfNeeded`).
enum HL7ACKBuilder {

    static func buildFallbackRejectACK(reason: String) -> String {
        let config = HL7Config.current
        let builder = HL7Builder.companion.builder()
            .defaultVersion(version: config.versionId)
            .build()

        let message = builder.ack { scope in
            scope.msh { msh in
                msh.sendingApplication = config.sendingApplication
                msh.sendingFacility = config.sendingFacility
                msh.receivingApplication = "UNKNOWN"
                msh.receivingFacility = "UNKNOWN"
                msh.dateTimeOfMessage = DateUtils.currentTimestamp()
                msh.messageControlId = UUID().uuidString
                msh.processingId = "P"
                msh.versionId = config.versionId
            }

            scope.msa { msa in
                msa.acknowledgmentCode = "AR"
                msa.messageControlId = ""
            }

            scope.err { err in
                err.errorText = reason
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
