//
//  FaceEnrollmentDuplicatePromptTests.swift
//  PillCounterTests
//
//  The duplicate prompt raised at the `.center` pose: that it publishes, that
//  answering it resumes without burning the enrollment budget, and that every
//  teardown path clears it. A real `.center` capture needs a camera, so these
//  drive runDuplicateCheck/continueAfterDuplicate directly — which is why those
//  are separate methods rather than inlined in captureStep.
//

import Foundation
import Testing
@testable import PillCounter

@Suite(.serialized)
@MainActor
struct FaceEnrollmentDuplicatePromptTests {

    private static func makeViewModel(
        _ stub: StubFaceRecognitionRepository
    ) -> FaceEnrollmentViewModel {
        FaceEnrollmentViewModel(repository: stub)
    }

    /// Mirrors what captureStep does before handing off to the main actor.
    private static func enterPausedCenterState(
        _ viewModel: FaceEnrollmentViewModel, attemptId: String, pausedFor: TimeInterval = 0
    ) {
        viewModel.pendingUserId = attemptId
        viewModel.isCapturingFrames = false
        viewModel.stepStartedAt = ProcessInfo.processInfo.systemUptime
        viewModel.duplicatePausedAt = ProcessInfo.processInfo.systemUptime - pausedFor
    }

    @Test func duplicateMatchPublishesPrompt() {
        let stub = StubFaceRecognitionRepository()
        stub.duplicateMatchResult = DuplicateFaceMatch(userId: "existing-1", userName: "Jane Doe")
        let viewModel = Self.makeViewModel(stub)
        let attemptId = UUID().uuidString
        Self.enterPausedCenterState(viewModel, attemptId: attemptId)

        viewModel.runDuplicateCheck(attemptId: attemptId, candidates: [])

        #expect(viewModel.duplicateMatch?.userId == "existing-1")
        #expect(viewModel.duplicateMatch?.userName == "Jane Doe")
        // Still paused — the prompt is the only thing that resumes it.
        #expect(viewModel.isCapturingFrames == false)
    }

    @Test func noDuplicateResumesSilently() {
        let stub = StubFaceRecognitionRepository()
        stub.duplicateMatchResult = nil
        let viewModel = Self.makeViewModel(stub)
        let attemptId = UUID().uuidString
        Self.enterPausedCenterState(viewModel, attemptId: attemptId)

        viewModel.runDuplicateCheck(attemptId: attemptId, candidates: [])

        #expect(viewModel.duplicateMatch == nil)
        #expect(viewModel.isCapturingFrames == true)
        #expect(viewModel.duplicatePausedAt == nil)
    }

    /// A result arriving after the attempt was torn down must not raise a
    /// prompt on a screen that is already gone.
    @Test func staleAttemptIsIgnored() {
        let stub = StubFaceRecognitionRepository()
        stub.duplicateMatchResult = DuplicateFaceMatch(userId: "existing-1", userName: "Jane Doe")
        let viewModel = Self.makeViewModel(stub)
        Self.enterPausedCenterState(viewModel, attemptId: UUID().uuidString)

        viewModel.runDuplicateCheck(attemptId: "a-different-attempt", candidates: [])

        #expect(viewModel.duplicateMatch == nil)
        #expect(stub.checkDuplicateFaceCallCount == 0)
    }

    @Test func continueAfterDuplicateClearsPromptAndResumes() {
        let stub = StubFaceRecognitionRepository()
        stub.duplicateMatchResult = DuplicateFaceMatch(userId: "existing-1", userName: "Jane Doe")
        let viewModel = Self.makeViewModel(stub)
        let attemptId = UUID().uuidString
        Self.enterPausedCenterState(viewModel, attemptId: attemptId)
        viewModel.runDuplicateCheck(attemptId: attemptId, candidates: [])

        viewModel.continueAfterDuplicate()

        #expect(viewModel.duplicateMatch == nil)
        #expect(viewModel.isCapturingFrames == true)
        #expect(viewModel.duplicatePausedAt == nil)
    }

    /// The reason `duplicatePausedAt` exists: time spent reading the prompt
    /// must not count against the step clock, or the next step's hint would
    /// escalate the instant capture resumes.
    @Test func continueAfterDuplicateRebasesStepClock() {
        let stub = StubFaceRecognitionRepository()
        stub.duplicateMatchResult = DuplicateFaceMatch(userId: "existing-1", userName: "Jane Doe")
        let viewModel = Self.makeViewModel(stub)
        let attemptId = UUID().uuidString
        let pausedFor: TimeInterval = 30
        Self.enterPausedCenterState(viewModel, attemptId: attemptId, pausedFor: pausedFor)
        let originBefore = viewModel.stepStartedAt
        viewModel.runDuplicateCheck(attemptId: attemptId, candidates: [])

        viewModel.continueAfterDuplicate()

        // Origin moved forward by roughly the pause, so elapsed-since-origin is
        // back to where it was when the prompt appeared. `advanceToNextStep`
        // then resets it to now, which is a further forward shift — so assert
        // the origin moved forward by AT LEAST the pause.
        let shift = viewModel.stepStartedAt - originBefore
        #expect(shift >= pausedFor - 1)
    }

    @Test func cancelEnrollmentClearsPrompt() {
        let stub = StubFaceRecognitionRepository()
        stub.duplicateMatchResult = DuplicateFaceMatch(userId: "existing-1", userName: "Jane Doe")
        let viewModel = Self.makeViewModel(stub)
        let attemptId = UUID().uuidString
        Self.enterPausedCenterState(viewModel, attemptId: attemptId)
        viewModel.runDuplicateCheck(attemptId: attemptId, candidates: [])

        viewModel.cancelEnrollment()

        #expect(viewModel.duplicateMatch == nil)
        #expect(viewModel.duplicatePausedAt == nil)
    }

    @Test func prepareForNextUserClearsPrompt() {
        let stub = StubFaceRecognitionRepository()
        stub.duplicateMatchResult = DuplicateFaceMatch(userId: "existing-1", userName: "Jane Doe")
        let viewModel = Self.makeViewModel(stub)
        let attemptId = UUID().uuidString
        Self.enterPausedCenterState(viewModel, attemptId: attemptId)
        viewModel.runDuplicateCheck(attemptId: attemptId, candidates: [])

        viewModel.prepareForNextUser()

        #expect(viewModel.duplicateMatch == nil)
        #expect(viewModel.duplicatePausedAt == nil)
    }
}
