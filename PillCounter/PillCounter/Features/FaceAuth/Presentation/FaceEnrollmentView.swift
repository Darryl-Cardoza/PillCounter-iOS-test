//
//  FaceEnrollmentView.swift
//  PillCounter
//
//  "Add New User" enrollment screen: name entry → guided pose capture (5
//  steps, one clear instruction at a time, progress dots, face oval that
//  changes color as pose is confirmed) → EnrollmentComplete. No
//  authentication/lock logic here — that is a separate future step.
//
//  Presented full-screen (selfie-camera only, no split preview/card) —
//  the capture stage fills the entire screen edge-to-edge, matching the
//  face-onboarding style used elsewhere in FaceAuth. On success this view
//  does NOT show its own "done" screen — it reports completion via
//  `onEnrolled` and dismisses immediately; the presenter (QuickAccessUsersView)
//  shows the success state as an overlay over the user list.
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
    /// Same instance as viewModel.cameraService — observed separately so
    /// SwiftUI re-renders (and re-runs updateUIView on the preview) when
    /// `cameraPosition` changes on flip. viewModel itself doesn't republish
    /// its cameraService's @Published changes.
    @ObservedObject private var cameraService: FaceEnrollmentCameraService
    @EnvironmentObject private var appColors: AppColors
    @Environment(\.dismiss) private var dismiss

    @State private var onboardingStep: OnboardingStep = .intro
    @State private var nameError: String?

    /// Fired once, right when enrollment succeeds, with the enrolled name —
    /// the presenter uses this to drive its own success overlay/dismiss.
    var onEnrolled: ((String) -> Void)?

    init(onEnrolled: ((String) -> Void)? = nil) {
        self.onEnrolled = onEnrolled
        let vm = FaceEnrollmentViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _cameraService = ObservedObject(wrappedValue: vm.cameraService)
    }

    var body: some View {
        Group {
            if viewModel.state == .idle {
                switch onboardingStep {
                case .intro:
                    introSection
                        .padding()
                        .background(appColors.secondaryBackground)
                case .nameEntry:
                    nameEntrySection
                        .padding()
                        .background(appColors.secondaryBackground)
                }
            } else {
                enrollmentCaptureSection
                    .background(Color.black)
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
            if newState == .enrollmentComplete {
                onEnrolled?(viewModel.trimmedName)
                dismiss()
            }
        }
    }

    // MARK: - Intro ("Setup Quick Access")

    private var introSection: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(appColors.text)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(appColors.primary.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                Image(systemName: "faceid")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(appColors.primary)
            }

            VStack(spacing: 10) {
                Text(L10n.FaceAuth.setupIntroTitle)
                    .font(.title3.bold())
                    .foregroundStyle(appColors.primary)

                Text(L10n.FaceAuth.setupIntroSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(appColors.text.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(L10n.FaceAuth.cancel) { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(appColors.primary)

                Button(L10n.FaceAuth.getStarted) {
                    onboardingStep = .nameEntry
                }
                .buttonStyle(.borderedProminent)
                .tint(appColors.primary)
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Name entry

    private var nameEntrySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    onboardingStep = .intro
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

            Button(L10n.FaceAuth.continueButton) {
                continueTapped()
            }
            .disabled(!viewModel.isNameValid)
            .buttonStyle(.borderedProminent)
            .tint(appColors.primary)
            .frame(maxWidth: .infinity)
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

    // MARK: - Capture (full-screen, selfie-camera only)

    private var enrollmentCaptureSection: some View {
        GeometryReader { geometry in
            ZStack {
                FaceEnrollmentCameraPreview(
                    session: cameraService.previewSession,
                    cameraPosition: cameraService.cameraPosition
                )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                Color.black.opacity(0.35)
                    .mask(
                        Rectangle()
                            .overlay(
                                Ellipse()
                                    .frame(width: geometry.size.height * 0.5, height: geometry.size.height * 0.72)
                                    .blendMode(.destinationOut)
                            )
                    )
                    .compositingGroup()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                Ellipse()
                    .stroke(ovalColor, lineWidth: 4)
                    .frame(width: geometry.size.height * 0.5, height: geometry.size.height * 0.72)

                topBar

                bottomGuidanceBar
            }
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    viewModel.cancelEnrollment()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }

                Spacer()

                if let progress = viewModel.stepProgress {
                    Text("\(progress.index + 1)/\(progress.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())
                }

                Spacer()

                flipCameraButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
        }
    }

    private var bottomGuidanceBar: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                if let progress = viewModel.stepProgress {
                    progressDots(index: progress.index, count: progress.count)
                }

                Text(viewModel.instructionText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 30)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.instructionText)

                if case .failed = viewModel.state {
                    HStack(spacing: 12) {
                        Button(L10n.FaceAuth.cancel) {
                            viewModel.cancelEnrollment()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button(L10n.FaceAuth.retry) { viewModel.retry() }
                            .buttonStyle(.borderedProminent)
                            .tint(appColors.primary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func progressDots(index: Int, count: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < index ? appColors.primary : (i == index ? appColors.primary.opacity(0.5) : Color.white.opacity(0.3)))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var ovalColor: Color {
        switch viewModel.state {
        case .enrollmentComplete: return .green
        case .failed: return .red
        case .poseHeld, .capturingSample: return .green
        case .awaitingPose: return appColors.primary
        default: return .gray
        }
    }

    private var flipCameraButton: some View {
        Button {
            viewModel.cameraService.flipCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
    }
}
