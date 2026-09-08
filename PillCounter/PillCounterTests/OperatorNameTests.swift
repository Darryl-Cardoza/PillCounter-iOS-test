//
//  OperatorNameTests.swift
//  PillCounterTests
//
//  OperatorName.current is the single source both UnifiedCameraView and
//  HL7MessageBuilder call for operator identification — see PR review note about
//  the two implementations that could drift.
//

import Testing
@testable import PillCounter

@Suite(.serialized)
struct OperatorNameTests {

    private func withFaceSessionName(_ name: String?, _ body: () -> Void) {
        let original = AppStorageManager.shared.faceLockCurrentUserName
        AppStorageManager.shared.faceLockCurrentUserName = name
        defer { AppStorageManager.shared.faceLockCurrentUserName = original }
        body()
    }

    @Test func prefersFaceSessionNameOverAccountName() {
        withFaceSessionName("Face User") {
            #expect(OperatorName.current(fname: "Account", lname: "Name") == "Face User")
        }
    }

    @Test func fallsBackToAccountNameWhenNoFaceSession() {
        withFaceSessionName(nil) {
            #expect(OperatorName.current(fname: "Jane", lname: "Doe") == "Jane Doe")
        }
    }

    @Test func fallsBackToAccountNameWhenFaceSessionNameIsBlank() {
        withFaceSessionName("   ") {
            #expect(OperatorName.current(fname: "Jane", lname: "Doe") == "Jane Doe")
        }
    }

    @Test func joinsOnlyNonEmptyNameParts() {
        withFaceSessionName(nil) {
            #expect(OperatorName.current(fname: "Jane", lname: nil) == "Jane")
            #expect(OperatorName.current(fname: nil, lname: "Doe") == "Doe")
            #expect(OperatorName.current(fname: nil, lname: nil) == "")
        }
    }

    @Test func trimsWhitespaceFromBothSources() {
        withFaceSessionName("  Face User  ") {
            #expect(OperatorName.current(fname: "Jane", lname: "Doe") == "Face User")
        }
        withFaceSessionName(nil) {
            #expect(OperatorName.current(fname: "  Jane  ", lname: "  Doe  ") == "Jane Doe")
        }
    }
}
