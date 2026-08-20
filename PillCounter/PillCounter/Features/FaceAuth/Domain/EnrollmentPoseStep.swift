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

    /// Target yaw in degrees, signed (+ = subject's right, i.e. turned
    /// toward camera-left in a mirrored front-camera preview). nil = no
    /// yaw requirement beyond the default centered tolerance.
    var targetYawDegrees: ClosedRange<Float>? {
        switch self {
        case .center, .centerAgain: return -10...10
        case .turnLeft: return 12...25
        case .turnRight: return -25...(-12)
        case .chinUp: return -10...10
        }
    }

    var targetPitchDegrees: ClosedRange<Float>? {
        switch self {
        case .chinUp: return 8...20
        default: return -10...10
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

    var next: EnrollmentPoseStep? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}
