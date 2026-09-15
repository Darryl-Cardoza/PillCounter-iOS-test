//
//  FaceAuthInstructionTextTests.swift
//  PillCounterTests
//
//  Regression guard for the verify-screen instruction flicker: the pipeline
//  publishes 4-5 state changes per processed frame at ~6.7 frames/sec, so any
//  scanning stage that maps to its own copy makes the text strobe — worst for
//  an unrecognized person, who loops detect -> compare -> no match until the
//  scan budget expires.
//

import Foundation
import Testing
@testable import PillCounter

@Suite(.serialized)
@MainActor
struct FaceAuthInstructionTextTests {

    /// Every stage of an in-progress scan must read identically. If someone
    /// gives one of these its own copy again, the flicker comes back.
    @Test func allScanningStagesShareOneMessage() {
        let viewModel = FaceAuthenticationViewModel()

        let scanningStates: [AuthenticationState] = [
            .faceDetected,
            .qualityChecking,
            .generatingEmbedding,
            .comparing,
            .candidateFound,
            .confirmingIdentity(passCount: 1, required: 2),
        ]

        let texts = scanningStates.map { state -> String in
            viewModel.state = state
            return viewModel.instructionText
        }

        #expect(Set(texts).count == 1)
        #expect(texts.first == L10n.FaceAuth.authVerifying)
    }

    /// No-face keeps its own actionable copy — nothing else on screen tells a
    /// user the camera cannot see them.
    @Test func noFaceKeepsItsOwnGuidanceCopy() {
        let viewModel = FaceAuthenticationViewModel()
        viewModel.state = .detectingFace

        #expect(viewModel.instructionText == L10n.FaceAuth.authDetecting)
        #expect(viewModel.instructionText != L10n.FaceAuth.authVerifying)
    }

    /// An expired scan budget surfaces as a terminal failure, which is what
    /// renders the Retry action — not as more scanning copy.
    @Test func expiredScanBudgetReadsAsUnrecognized() {
        let viewModel = FaceAuthenticationViewModel()
        viewModel.state = .failed(.unknownUser)

        #expect(viewModel.instructionText == L10n.FaceAuth.authUnknownUser)
    }

    @Test func authenticatedStateNamesTheUser() {
        let viewModel = FaceAuthenticationViewModel()
        viewModel.state = .authenticated(userName: "Bb Bb")

        #expect(viewModel.instructionText.contains("Bb Bb"))
    }
}
