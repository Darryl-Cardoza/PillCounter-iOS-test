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
    @ObservedObject private var cameraService: FaceCameraService
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
        ZStack {
            FaceScanScreen(
                cameraService: cameraService,
                state: viewModel.state,
                instructionText: viewModel.instructionText,
                showsFlipCamera: true,
                onBack: { dismiss() }
            )

            // Terminal states get their own controls layered over the
            // preview; while scanning, the back control is the only action.
            if isTerminalState {
                VStack {
                    Spacer()
                    actionButtons
                        .padding(.bottom, 80)
                }
            }
        }
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

    private var isTerminalState: Bool {
        switch viewModel.state {
        case .authenticated, .failed: return true
        default: return false
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch viewModel.state {
        case .authenticated:
            FaceAuthActionButton(title: L10n.FaceAuth.authContinue, isPrimary: true) { dismiss() }
        case .failed:
            HStack(spacing: 12) {
                FaceAuthActionButton(title: L10n.FaceAuth.authCancel, isPrimary: false) { dismiss() }
                FaceAuthActionButton(title: L10n.FaceAuth.retry, isPrimary: true) { viewModel.retry() }
            }
        default:
            EmptyView()
        }
    }
}

/// Themed wrapper over the app's shared PillCountingButton, so every face-auth
/// screen renders the same pill-shaped control instead of SwiftUI's stock
/// `.bordered` / `.borderedProminent` styles.
struct FaceAuthActionButton: View {

    @EnvironmentObject private var appColors: AppColors

    let title: String
    let isPrimary: Bool
    let isEnabled: Bool
    let fillsWidth: Bool
    let action: () -> Void

    init(
        title: String,
        isPrimary: Bool,
        isEnabled: Bool = true,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isPrimary = isPrimary
        self.isEnabled = isEnabled
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        PillCountingButton(
            iconName: nil,
            title: title,
            textColor: isPrimary ? .white : appColors.primary,
            backgroundColor: isPrimary ? appColors.primary : .clear,
            borderColor: isPrimary ? .clear : appColors.primary,
            font: .system(size: 15, weight: .semibold),
            cornerRadius: 30,
            horizontalPadding: 28,
            verticalPadding: 16,
            iconSize: 0,
            action: action
        )
        .modifier(FaceAuthButtonWidth(fillsWidth: fillsWidth))
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }
}

/// `.fixedSize()` and `.frame(maxWidth:)` produce different view types, so the
/// choice has to go through a modifier rather than an inline conditional.
private struct FaceAuthButtonWidth: ViewModifier {

    let fillsWidth: Bool

    func body(content: Content) -> some View {
        if fillsWidth {
            content.frame(maxWidth: .infinity)
        } else {
            content.fixedSize()
        }
    }
}
