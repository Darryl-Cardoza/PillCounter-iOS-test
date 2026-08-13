//
//  FaceQualityResult.swift
//  PillCounter
//

/// Reason a frame's face detection was rejected by FaceQualityChecker.
/// Drives the on-screen enrollment instruction text.
enum FaceQualityRejectionReason {
    case faceNotFound
    case multipleFaces
    case faceTooSmall
    case faceTooClose
    case faceTooFar
    case lowConfidence
    case faceTooBlurry
    case facePoorlyPositioned
    case faceTooMuchRotation
    case faceCropIncomplete
    case invalidLandmarks
}

/// Result of FaceQualityChecker.check(_:). `isAcceptable == true` means the
/// detection passed every HARD gate and is safe to align + pass to SFace.
/// `yawDegrees`/`pitchDegrees` are coarse pose estimates used by the guided
/// enrollment flow to decide whether the current pose step's target has
/// been reached — they are not gating criteria themselves.
struct FaceQualityResult {
    let isAcceptable: Bool
    let reason: FaceQualityRejectionReason?
    /// 0...1, higher is better. Present even on rejection for diagnostics/UI.
    let qualityScore: Float
    let yawDegrees: Float
    let pitchDegrees: Float

    static func accepted(qualityScore: Float, yawDegrees: Float = 0, pitchDegrees: Float = 0) -> FaceQualityResult {
        FaceQualityResult(isAcceptable: true, reason: nil, qualityScore: qualityScore,
                          yawDegrees: yawDegrees, pitchDegrees: pitchDegrees)
    }

    static func rejected(_ reason: FaceQualityRejectionReason, qualityScore: Float = 0) -> FaceQualityResult {
        FaceQualityResult(isAcceptable: false, reason: reason, qualityScore: qualityScore,
                          yawDegrees: 0, pitchDegrees: 0)
    }
}
