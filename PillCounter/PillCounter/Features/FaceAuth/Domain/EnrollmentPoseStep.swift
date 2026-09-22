//
//  EnrollmentPoseStep.swift
//  PillCounter
//
//  Guided pose sequence for enrollment. ArcFace-family recognizers (SFace
//  included) are trained on roughly-frontal faces — extreme poses hurt
//  match accuracy rather than help it, so every step stays near-frontal.
//  The point of guiding the user through distinct poses is UX clarity +
//  a light liveness signal (head must actually move), not embedding
//  diversity for its own sake.
//

import Foundation

enum EnrollmentPoseStep: Int, CaseIterable {
    case center
    case turnLeft
    case turnRight
    case chinUp
    case centerAgain

    /// Target yaw in degrees, signed (+ = turned toward the subject's own
    /// left, matching FaceQualityChecker.yawDegreesEstimate). nil = no yaw
    /// requirement beyond the default centered tolerance.
    var targetYawDegrees: ClosedRange<Float>? {
        switch self {
        case .center, .centerAgain: return -10...10
        // Widened from 12...25 / -25...(-12) (13° window) to match center's
        // 20° tolerance — the underlying yaw estimate is the same noisy
        // nose-offset ratio heuristic used for every step (see
        // FaceQualityChecker.yawDegreesEstimate), so giving it a narrower
        // window here than elsewhere made the same absolute jitter
        // proportionally much more disruptive, independent of how fast or
        // slow the user actually turned.
        case .turnLeft: return 10...30
        case .turnRight: return -30...(-10)
        case .chinUp: return -12...12
        }
    }

    /// + = chin up. Range is wide on the upper end because the landmark-only
    /// pitch proxy saturates fast once the nostrils occlude the nose tip.
    var targetPitchDegrees: ClosedRange<Float>? {
        switch self {
        case .chinUp: return 6...30
        default: return -12...12
        }
    }

    var instructionKey: String {
        switch self {
        case .center: return L10n.FaceAuth.poseCenter
        case .turnLeft: return L10n.FaceAuth.poseTurnLeft
        case .turnRight: return L10n.FaceAuth.poseTurnRight
        case .chinUp: return L10n.FaceAuth.poseChinUp
        case .centerAgain: return L10n.FaceAuth.poseCenterAgain
        }
    }

    /// Firmer wording once the user has been stuck on this step for a while
    /// (see FaceEnrollmentViewModel.escalateAfterSeconds). Only the turns have
    /// one — "center your face" can't be usefully restated, which is also why
    /// Android only escalates its two tilts.
    var escalatedInstructionKey: String? {
        switch self {
        case .turnLeft: return L10n.FaceAuth.poseTurnLeftFurther
        case .turnRight: return L10n.FaceAuth.poseTurnRightFurther
        case .center, .chinUp, .centerAgain: return nil
        }
    }

    /// Voiceover text for this step — center/turnLeft/turnRight use Android's
    /// exact spoken-strings-reference.md copy (distinct from instructionKey's
    /// on-screen wording); chinUp/centerAgain have no Android equivalent, so
    /// they simply speak their own display text.
    var spokenKey: String {
        switch self {
        case .center: return L10n.FaceAuth.spokenPoseCenter
        case .turnLeft: return L10n.FaceAuth.spokenPoseTurnLeft
        case .turnRight: return L10n.FaceAuth.spokenPoseTurnRight
        case .chinUp, .centerAgain: return instructionKey
        }
    }

    var next: EnrollmentPoseStep? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}
