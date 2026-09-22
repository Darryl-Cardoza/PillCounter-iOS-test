//
//  EnrollmentState.swift
//  PillCounter
//

/// Explicit failure states surfaced to the enrollment UI.
enum EnrollmentFailureReason {
    case noFace
    case multipleFaces
    case poorQuality(FaceQualityRejectionReason)
    case embeddingGenerationFailed
    case cameraError(String)
    case storageError
    /// Global enrollment timeout expired with too few usable samples
    /// (spec: never loop forever — see FaceEnrollmentViewModel).
    case timedOut
    /// The face being captured no longer matches the one that captured the
    /// `.center` step — either a different person stepped in, or no usable
    /// face was seen for too long. See FaceEnrollmentViewModel's
    /// boxMatchesAnchor/restartForBrokenTrack. Only reachable as defense in
    /// depth now — a broken track restarts the scan rather than failing it.
    case differentFaceDetected
}

/// Enrollment capture state machine, driven by a guided pose sequence
/// (EnrollmentPoseStep) rather than "collect N embeddings from anywhere."
/// `currentStep`/`stepIndex`/`stepCount` back the on-screen progress dots.
enum EnrollmentState: Equatable {
    case idle
    case preparing
    /// Actively working on one pose step: waiting for/confirming/capturing.
    case awaitingPose(step: EnrollmentPoseStep, stepIndex: Int, stepCount: Int)
    case poseHeld(step: EnrollmentPoseStep, stepIndex: Int, stepCount: Int)
    case capturingSample(step: EnrollmentPoseStep, stepIndex: Int, stepCount: Int)
    case enrollmentComplete
    case failed(EnrollmentFailureReason)

    static func == (lhs: EnrollmentState, rhs: EnrollmentState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.enrollmentComplete, .enrollmentComplete):
            return true
        case let (.awaitingPose(s1, i1, c1), .awaitingPose(s2, i2, c2)):
            return s1 == s2 && i1 == i2 && c1 == c2
        case let (.poseHeld(s1, i1, c1), .poseHeld(s2, i2, c2)):
            return s1 == s2 && i1 == i2 && c1 == c2
        case let (.capturingSample(s1, i1, c1), .capturingSample(s2, i2, c2)):
            return s1 == s2 && i1 == i2 && c1 == c2
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}
