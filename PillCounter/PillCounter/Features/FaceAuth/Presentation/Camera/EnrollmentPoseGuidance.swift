//
//  EnrollmentPoseGuidance.swift
//  PillCounter
//
//  Enrollment-only direction arrows, stacked below the shared FaceScanScreen's
//  instruction pill (which supplies the "Tilt face to your left" copy and the
//  in-flight spinner).
//
//  All three arrows are permanently on screen — only which one is
//  *highlighted* changes. Showing and hiding controls as the pose estimate
//  comes and goes made the row flicker, so nothing here is conditionally
//  rendered; a lost face just means no arrow is lit.
//
//  The highlight itself is derived from live pipeline state (current pose step
//  target vs. measured yaw/pitch), never from a timer or a "next" button.
//

import SwiftUI

/// Which way the user still has to move for the current step to be satisfied.
/// `.onTarget` means the pose is in range and only needs holding.
enum PoseNudge: Equatable {
    case turnLeft
    case turnRight
    case chinUp
    case chinDown
    case onTarget

    /// Derives the nudge from the live pose estimate against the step's
    /// target ranges. Yaw is checked before pitch: a face turned away is the
    /// bigger correction, and asking for two adjustments at once reads as
    /// contradictory guidance.
    static func from(step: EnrollmentPoseStep, yawDegrees: Float, pitchDegrees: Float) -> PoseNudge {
        if let yaw = step.targetYawDegrees, !yaw.contains(yawDegrees) {
            return yawDegrees < yaw.lowerBound ? .turnLeft : .turnRight
        }
        if let pitch = step.targetPitchDegrees, !pitch.contains(pitchDegrees) {
            return pitchDegrees < pitch.lowerBound ? .chinUp : .chinDown
        }
        return .onTarget
    }
}

struct EnrollmentPoseGuidance: View {

    @EnvironmentObject private var appColors: AppColors

    /// nil when there is nothing to point at (no usable face in frame, pose
    /// already on target). The arrows stay put; none of them lights up.
    let nudge: PoseNudge?

    /// Steps already captured. Once a direction's step lands here, that slot
    /// freezes to `done_icon` and stops following `nudge` — otherwise it kept
    /// blinking on/off with live head movement after the sample was already
    /// taken.
    let completedSteps: Set<EnrollmentPoseStep>

    /// Left / up / right, matching the reference mock. Always all three, in
    /// place; the required correction is the lit one. Boxed together (rather
    /// than floating loose over the preview) so the row reads as one control,
    /// matching the instruction pill's treatment above it.
    var body: some View {
        HStack(spacing: 22) {
            arrow(systemName: "arrow.left", isActive: nudge == .turnLeft, isDone: completedSteps.contains(.turnLeft))
            arrow(systemName: "arrow.up", isActive: nudge == .chinUp, isDone: completedSteps.contains(.chinUp))
            arrow(systemName: "arrow.right", isActive: nudge == .turnRight, isDone: completedSteps.contains(.turnRight))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.75))
        )
        .animation(.easeInOut(duration: 0.2), value: nudge)
        .padding(.bottom, 14)
    }

    private func arrow(systemName: String, isActive: Bool, isDone: Bool) -> some View {
        Group {
            if isDone {
                Image("done_icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(11)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isActive ? .white : Color.black.opacity(0.75))
            }
        }
        .frame(width: 46, height: 46)
        .background(
            Circle().fill(isDone || isActive ? appColors.primary : Color.white.opacity(0.9))
        )
    }
}
