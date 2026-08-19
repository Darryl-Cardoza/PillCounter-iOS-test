//
//  FaceEnrollmentView.swift
//  PillCounter
//
//  "Add New User" enrollment screen: name entry → guided pose capture (5
//  steps, one clear instruction at a time, progress dots, face oval that
//  changes color as pose is confirmed) → EnrollmentComplete. No
//  authentication/lock logic here — that is a separate future step.
//
//  The capture stage reuses FaceScanScreen — the exact viewfinder the
//  authentication/unlock flow shows — so both screens look identical. The
//  only enrollment-specific chrome is injected into that screen's guidance
//  slot: a directional arrow row and a capture progress bar, both driven by
//  live pipeline state (pose estimate + samples captured), never by a timer
//  or a manual "next" button.
//
//  Terminal states get their own SessionStatusScreen — the same ringed-icon
//  layout the session lock/unlock screens use — with ADD USER + DONE actions.
//  Completion is still reported via `onEnrolled` so the presenter can refresh
//  its list, but this view owns the success screen rather than dismissing
//  straight into an overlay.
//

import SwiftUI

struct FaceEnrollmentView: View {

    /// Pre-capture onboarding steps shown before the ViewModel's own
    /// `.idle` → guided-capture state machine ever starts — these are pure
    /// UI, the ViewModel has no notion of "intro"/"name form".
    private enum OnboardingStep {
        case intro
        case nameEntry
    }

    @StateObject private var viewModel: FaceEnrollmentViewModel

    /// Always the camera owned by the SURVIVING view model, never a snapshot
    /// taken in `init`.
    ///
    /// SwiftUI re-runs `init` on every re-render of the presenting view, so a
    /// second FaceEnrollmentViewModel (and a second FaceCameraService) is
    /// constructed each time. `@StateObject` keeps the first and discards the
    /// duplicate — but an `@ObservedObject` initialized in `init` captured the
    /// DISCARDED instance's camera. The flip button then reconfigured a session
    /// nobody was previewing, so flipping appeared to do nothing. This showed
    /// up from Quick Access Users, whose `reload()` mutates @State while the
    /// enrollment cover is presented and therefore forces exactly that
    /// re-render.
    ///
    /// The view model forwards the camera's `@Published` changes (see its
    /// cameraService subscription), so reading through it still re-renders the
    /// preview on flip.
    private var cameraService: FaceCameraService { viewModel.cameraService }
    @EnvironmentObject private var appColors: AppColors
    @Environment(\.dismiss) private var dismiss

    @State private var onboardingStep: OnboardingStep = .intro
    @State private var nameError: String?

    /// Fired once, right when enrollment succeeds, with the enrolled name —
    /// the presenter uses this to drive its own success overlay/dismiss.
    var onEnrolled: ((String) -> Void)?

    /// Whether `.intro` is a reachable step at all — decides where name
    /// entry's back button goes.
    private let showsIntro: Bool

    /// The "Setup Quick Access" pitch is first-run onboarding — it explains
    /// what face unlock is for. Once at least one user is enrolled that pitch
    /// is noise, so the presenter passes `false` and the flow opens straight
    /// on name entry.
    init(showsIntro: Bool = true, onEnrolled: ((String) -> Void)? = nil) {
        self.onEnrolled = onEnrolled
        self.showsIntro = showsIntro
        _viewModel = StateObject(wrappedValue: FaceEnrollmentViewModel())
        _onboardingStep = State(initialValue: showsIntro ? .intro : .nameEntry)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                switch onboardingStep {
                case .intro:
                    introSection
                        .background(appColors.primaryBackground)
                        .ignoresSafeArea()
                case .nameEntry:
                    nameEntrySection
                        .padding()
                        .background(appColors.secondaryBackground)
                }

            case .enrollmentComplete:
                enrolledSection
                    .background(appColors.primaryBackground)
                    .ignoresSafeArea()

            case .failed:
                failedSection
                    .background(appColors.primaryBackground)
                    .ignoresSafeArea()

            default:
                enrollmentCaptureSection
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            // Face capture geometry (YuNet/SFace alignment) assumes a fixed
            // interface orientation — rotating mid-scan shifts the camera
            // buffer's orientation relative to what was captured at
            // enrollment, which corrupts alignment and produces wrong
            // embeddings. Lock to whichever orientation matches how each
            // device class is actually held for a selfie-style capture
            // (portrait on iPhone, landscape on iPad — non-negotiable).
            OrientationLock.shared.lockForFaceCapture()
        }
        .onDisappear {
            OrientationLock.shared.unlock()
            if viewModel.state != .enrollmentComplete {
                viewModel.cancelEnrollment()
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            // Fire once so the presenter can reload its list behind us; the
            // success screen itself stays up until the user picks an action.
            if newState == .enrollmentComplete {
                onEnrolled?(viewModel.trimmedName)
            }
        }
    }

    // MARK: - Intro ("Setup Quick Access")

    /// Same ringed-icon layout as the session lock / enrolled screens, so all
    /// four states in this feature read as one design. Only shown when the
    /// caller asks for it — see `showsIntro`.
    private var introSection: some View {
        SessionStatusScreen(
            iconName: "icon_face_scan",
            title: L10n.FaceAuth.setupIntroTitle,
            subtitle: L10n.FaceAuth.setupIntroSubtitle,
            subtitleMaxWidth: 320
        ) {
            SessionActionButtonPair(
                cancelTitle: L10n.FaceAuth.cancel,
                confirmTitle: L10n.FaceAuth.getStarted,
                onCancel: { dismiss() },
                onConfirm: { onboardingStep = .nameEntry }
            )
        }
    }

    // MARK: - Name entry

    private var nameEntrySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    // With no intro step behind us, back means "leave".
                    if showsIntro {
                        onboardingStep = .intro
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(appColors.text)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(appColors.text)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.FaceAuth.whatsYourName)
                    .font(.title3.bold())
                    .foregroundStyle(appColors.primary)

                Text(L10n.FaceAuth.whatsYourNameSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(appColors.text.opacity(0.7))
            }

            TextField(L10n.FaceAuth.firstNameFieldPlaceholder, text: $viewModel.firstName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            TextField(L10n.FaceAuth.lastNameFieldPlaceholder, text: $viewModel.lastName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            if let nameError {
                Text(nameError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Spacer()

            FaceAuthActionButton(
                title: L10n.FaceAuth.continueButton,
                isPrimary: true,
                isEnabled: viewModel.isNameValid,
                fillsWidth: true
            ) {
                continueTapped()
            }
            .padding(.bottom, 12)
        }
    }

    private func continueTapped() {
        guard viewModel.isNameValid else {
            nameError = L10n.FaceAuth.nameEmptyError
            return
        }
        guard viewModel.validateNameBeforeStarting() else {
            nameError = L10n.FaceAuth.nameDuplicateError
            return
        }
        nameError = nil
        viewModel.startEnrollment()
    }

    // MARK: - Capture (shared viewfinder + enrollment guidance)

    /// Identical to the authentication/unlock viewfinder — only the
    /// instruction text and the injected guidance differ. `state` is a
    /// placeholder because enrollment drives colour/spinner through the
    /// explicit overrides instead of AuthenticationState.
    private var enrollmentCaptureSection: some View {
        FaceScanScreen(
            cameraService: cameraService,
            state: .idle,
            instructionText: viewModel.instructionText,
            title: L10n.FaceAuth.enrollmentTitle,
            showsFlipCamera: true,
            isBusy: viewModel.isBusy,
            guideColorOverride: guideColor,
            onBack: {
                viewModel.cancelEnrollment()
                dismiss()
            },
            guidance: {
                EnrollmentPoseGuidance(nudge: viewModel.poseNudge)
            }
        )
    }

    /// Green once the pose is locked in and being captured, on-brand while
    /// still waiting for it.
    private var guideColor: Color {
        switch viewModel.state {
        case .poseHeld, .capturingSample: return appColors.secondary
        default: return appColors.primary
        }
    }

    // MARK: - Terminal states

    private var enrolledSection: some View {
        SessionStatusScreen(
            iconName: "done_icon",
            title: L10n.FaceAuth.enrollmentCompleteTitle,
            subtitle: L10n.FaceAuth.enrollmentCompleteSubtitle
        ) {
            SessionActionButtonPair(
                cancelTitle: L10n.FaceAuth.quickAccessUsersAddUser,
                confirmTitle: L10n.FaceAuth.done,
                onCancel: startAnotherEnrollment,
                onConfirm: { dismiss() }
            )
        }
    }

    private var failedSection: some View {
        SessionStatusScreen(
            iconName: "icon_close",
            title: L10n.FaceAuth.enrollmentFailedTitle,
            subtitle: viewModel.instructionText
        ) {
            SessionActionButtonPair(
                cancelTitle: L10n.FaceAuth.cancel,
                confirmTitle: L10n.FaceAuth.retry,
                onCancel: {
                    viewModel.cancelEnrollment()
                    dismiss()
                },
                onConfirm: { viewModel.retry() }
            )
        }
    }

    /// "Add User" from the success screen: clear the previous name and drop
    /// back to name entry rather than re-capturing for the same person.
    private func startAnotherEnrollment() {
        viewModel.prepareForNextUser()
        nameError = nil
        onboardingStep = .nameEntry
    }
}
