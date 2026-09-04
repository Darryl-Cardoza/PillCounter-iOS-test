//
//  HL7ValidationTests.swift
//  PillCounterTests
//
//  Confirms the linked Hl7Core.xcframework's HL7Validator actually rejects a
//  malformed RDE^O11 dispense message (non-numeric/negative RXE-3 quantity)
//  with AR, instead of the app silently accepting every message regardless
//  of content. Exercises HL7.parse(raw:)/validate(message:)/ack(message:)
//  directly — the same calls Hl7ServiceManager.startServerIfNeeded makes —
//  so a stale/rebuilt framework mismatch shows up here without needing the
//  full MLLP server/transport stack.
//

import Testing
import Hl7Core
@testable import PillCounter

@Suite
struct HL7ValidationTests {

    private func rdeMessage(controlId: String, ndc: String, quantity: String) -> String {
        [
            "MSH|^~\\&|PMS|PMS|PillCounter|PillCounter|20260101120000||RDE^O11|\(controlId)|P|2.3",
            "ORC|NW|RX\(controlId)",
            "RXE||\(ndc)^Test Drug^NDC|\(quantity)|EA"
        ].joined(separator: "\r")
    }

    private func hl7() -> HL7 {
        HL7(version: "2.3", strictMode: false, validationConfig: .companion.DEFAULT, extraSegments: [])
    }

    @Test func negativeQuantityIsRejectedWithAR() {
        let raw = rdeMessage(controlId: "CTRL-NEG-1", ndc: "00000-001-01", quantity: "-5")

        let result = hl7().parse(raw: raw)
        guard let success = result as? HL7ParseResult.Success else {
            Issue.record("expected message to parse structurally; got \(result)")
            return
        }

        let validation = hl7().validate(message: success.message)
        #expect(validation.worst == .reject, "negative RXE-3 quantity must reject, issues: \(validation.issues.map { $0.errorText })")

        let ack = hl7().ack(message: success.message)
        #expect(ack.contains("|AR|"), "ACK for a rejected message must carry MSA-1=AR, got: \(ack)")
    }

    @Test func nonNumericQuantityIsRejectedWithAR() {
        let raw = rdeMessage(controlId: "CTRL-NAN-1", ndc: "00000-001-01", quantity: "abc")

        guard let success = hl7().parse(raw: raw) as? HL7ParseResult.Success else {
            Issue.record("expected message to parse structurally")
            return
        }

        let validation = hl7().validate(message: success.message)
        #expect(validation.worst == .reject, "non-numeric RXE-3 quantity must reject, issues: \(validation.issues.map { $0.errorText })")
    }

    @Test func validPositiveQuantityIsAccepted() {
        let raw = rdeMessage(controlId: "CTRL-OK-1", ndc: "00000-001-01", quantity: "30")

        guard let success = hl7().parse(raw: raw) as? HL7ParseResult.Success else {
            Issue.record("expected message to parse structurally")
            return
        }

        let validation = hl7().validate(message: success.message)
        #expect(validation.worst == .accept, "valid positive quantity must accept, issues: \(validation.issues.map { $0.errorText })")

        let ack = hl7().ack(message: success.message)
        #expect(ack.contains("|AA|"), "ACK for an accepted message must carry MSA-1=AA, got: \(ack)")
    }
}
