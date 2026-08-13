//
//  FaceAuthenticationView.swift
//  PillCounter
//
//  Face-unlock / Quick Access screen (spec section 1). Shows camera preview,
//  positioning guidance, a processing indicator while a frame is being
//  verified, and error/retry UI. The authenticated user's name is revealed
//  ONLY after `state` becomes `.authenticated` — no registered name, no
//  similarity score, is ever shown before or on failure.
//

import SwiftUI

struct FaceAuthenticationView: View {

    @StateObject private var viewModel: FaceAuthenticationViewModel
    /// Same instance as viewModel.cameraService — observed separately so
    /// SwiftUI re-renders (and re-runs updateUIView on the preview) when
    /// `cameraPosition` changes on flip. See FaceEnrollmentView for why
    /// viewModel itself can't be relied on to republish this.
    @ObservedObject private var cameraService: FaceEnrollmentCameraService
    @EnvironmentObject private var appColors: AppColors
    @Environment(\.dismiss) private var dismiss

    /// Called once, right after `onAuthenticated` fires, so the presenter
    /// can unlock / reset the inactivity timer / restore prior app state
    /// (spec section 14). Distinct from onAuthenticated on the ViewModel so
    /// this view stays a plain, reusable "scan and report" screen.
    var onAuthenticated: ((_ userId: String, _ userName: String) -> Void)?

    init(onAuthenticated: ((_ userId: String, _ userName: String) -> Void)? = nil) {
        self.onAuthenticated = onAuthenticated
        let vm = FaceAuthenticationViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _cameraService = ObservedObject(wrappedValue: vm.cameraService)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.FaceAuth.authTitle)
                .font(.title3.bold())
                .foregroundStyle(appColors.text)

            ZStack {
                FaceEnrollmentCameraPreview(
                    session: cameraService.previewSession,
                    cameraPosition: cameraService.cameraPosition
                )
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                RoundedRectangle(cornerRadius: 100)
                    .stroke(ovalColor, lineWidth: 4)
                    .padding(40)

                if isProcessingFrame {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }

                flipCameraButton
            }

            Text(viewModel.instructionText)
                .font(.headline)
                .foregroundStyle(appColors.text)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .animation(.easeInOut(duration: 0.2), value: viewModel.instructionText)

            actionButtons
        }
        .padding()
        .background(appColors.secondaryBackground)
        .onAppear {
            // See FaceEnrollmentView — same reasoning: fixed orientation
            // during capture keeps the camera buffer's geometry consistent
            // with what enrollment produced, so alignment/embeddings match.
            OrientationLock.shared.lockForFaceCapture()
            viewModel.onAuthenticated = { userId, userName in
                onAuthenticated?(userId, userName)
            }
            viewModel.startAuthentication()
        }
        .onDisappear {
            OrientationLock.shared.unlock()
            viewModel.stopAuthentication()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch viewModel.state {
        case .authenticated:
            Button(L10n.FaceAuth.authContinue) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(appColors.primary)
        case .failed:
            HStack(spacing: 12) {
                Button(L10n.FaceAuth.authCancel) { dismiss() }
                    .buttonStyle(.bordered)
                Button(L10n.FaceAuth.retry) { viewModel.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(appColors.primary)
            }
        default:
            Button(L10n.FaceAuth.authCancel) { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    private var isProcessingFrame: Bool {
        switch viewModel.state {
        case .faceDetected, .qualityChecking, .generatingEmbedding, .comparing, .candidateFound, .confirmingIdentity:
            return true
        default:
            return false
        }
    }

    private var ovalColor: Color {
        switch viewModel.state {
        case .authenticated: return .green
        case .failed: return .red
        case .transientIssue: return .orange
        case .confirmingIdentity, .candidateFound: return appColors.primary
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
