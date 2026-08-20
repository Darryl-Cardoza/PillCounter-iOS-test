//
//  AuthenticationState.swift
//  PillCounter
//

/// Authentication capture state machine (spec section 9). Linear happy path
/// plus explicit failure states — mirrors EnrollmentState's shape.
enum AuthenticationState: Equatable {
    case idle
    case startingCamera
    case detectingFace
    case faceDetected
    case qualityChecking
    case generatingEmbedding
    case comparing
    /// A candidate passed the acceptance threshold on this frame but the
    /// multi-frame confirmation rule hasn't been satisfied yet.
    case candidateFound
    case confirmingIdentity(passCount: Int, required: Int)
    case authenticated(userName: String)
    /// Non-terminal guidance — scanning continues (spec section 11: "do not
    /// authenticate, continue scanning" for multiple faces; the same applies
    /// to a poor-quality frame). Distinct from `.failed`, which is reserved
    /// for terminal outcomes the UI should stop and offer Retry for.
    case transientIssue(AuthenticationFailureReason)
    case failed(AuthenticationFailureReason)

    static func == (lhs: AuthenticationState, rhs: AuthenticationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.startingCamera, .startingCamera), (.detectingFace, .detectingFace),
             (.faceDetected, .faceDetected), (.qualityChecking, .qualityChecking),
             (.generatingEmbedding, .generatingEmbedding), (.comparing, .comparing),
             (.candidateFound, .candidateFound):
            return true
        case let (.confirmingIdentity(p1, r1), .confirmingIdentity(p2, r2)):
            return p1 == p2 && r1 == r2
        case let (.authenticated(n1), .authenticated(n2)):
            return n1 == n2
        case (.transientIssue, .transientIssue):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}
