//
//  AuthenticationResult.swift
//  PillCounter
//

import Foundation

/// A single frame's identification outcome against the loaded registered
/// users (FaceRecognitionRepository.identify). Internal to the recognition
/// pipeline — the UI layer never sees raw scores (spec section 1/15: "Do not
/// expose similarity scores to the user").
struct FrameIdentification {
    /// nil when no user's candidate score reached the acceptance threshold.
    let userId: String?
    /// Only meaningful for logging/tests — never surfaced in UI text.
    let score: Float
}

/// Outcome of a completed authentication session.
enum AuthenticationResult {
    case authenticated(userId: String, userName: String)
    case failed(AuthenticationFailureReason)
}

enum AuthenticationFailureReason {
    case noFace
    case multipleFaces
    case poorQuality(FaceQualityRejectionReason)
    case unknownUser
    case embeddingGenerationFailed
    case cameraError(String)
    case noRegisteredUsers
}
