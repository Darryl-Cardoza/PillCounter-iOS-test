//
//  FaceEnrollmentView.swift
//  PillCounter
//
//  "Add New User" enrollment screen: name entry → guided pose capture (5
//  steps, one clear instruction at a time, progress dots, face oval that
//  changes color as pose is confirmed) → EnrollmentComplete. No
//  authentication/lock logic here — that is a separate future step.
//

import SwiftUI

struct FaceEnrollmentView: View {

    @StateObject private var viewModel = FaceEnrollmentViewModel()
    @EnvironmentObject private var appColors: AppColors
    @Environment(\.dismiss) private var dismiss

    @State private var nameError: String?

    var body: some View {
        VStack(spacing: 24) {
            if viewModel.state == .idle {
                nameEntrySection
            } else {
                enrollmentCaptureSection
            }
        }
        .padding()
        .background(appColors.secondaryBackground)
        .onDisappear {
            if viewModel.state != .enrollmentComplete {
                viewModel.cancelEnrollment()
            }
        }
    }

    // MARK: - Name entry

    private var nameEntrySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.FaceAuth.enrollmentTitle)
                .font(.title3.bold())
                .foregroundStyle(appColors.text)

            TextField(L10n.FaceAuth.nameFieldPlaceholder, text: $viewModel.name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            if let nameError {
                Text(nameError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button(L10n.FaceAuth.startEnrollment) {
                startTapped()
            }
            .disabled(!viewModel.isNameValid)
            .buttonStyle(.borderedProminent)
            .tint(appColors.primary)

            Spacer()
        }
    }

    private func startTapped() {
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

    // MARK: - Capture

    private var enrollmentCaptureSection: some View {
        VStack(spacing: 20) {
            if let progress = viewModel.stepProgress {
                progressDots(index: progress.index, count: progress.count)
            }

            ZStack {
                FaceEnrollmentCameraPreview(session: viewModel.cameraService.previewSession)
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                RoundedRectangle(cornerRadius: 100)
                    .stroke(ovalColor, lineWidth: 4)
                    .padding(40)

                flipCameraButton
            }

            Text(viewModel.instructionText)
                .font(.headline)
                .foregroundStyle(appColors.text)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .animation(.easeInOut(duration: 0.2), value: viewModel.instructionText)

            if viewModel.state == .enrollmentComplete {
                Button(L10n.FaceAuth.done) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(appColors.primary)
            } else if case .failed = viewModel.state {
                HStack(spacing: 12) {
                    Button(L10n.FaceAuth.cancel) { viewModel.cancelEnrollment() }
                        .buttonStyle(.bordered)
                    Button(L10n.FaceAuth.retry) { viewModel.retry() }
                        .buttonStyle(.borderedProminent)
                        .tint(appColors.primary)
                }
            } else {
                Button(L10n.FaceAuth.cancel) {
                    viewModel.cancelEnrollment()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func progressDots(index: Int, count: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < index ? appColors.primary : (i == index ? appColors.primary.opacity(0.5) : Color.gray.opacity(0.3)))
                    .frame(width: 10, height: 10)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(16)
    }
}
