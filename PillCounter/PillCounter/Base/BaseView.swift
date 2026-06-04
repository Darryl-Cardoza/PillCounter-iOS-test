//
//  BaseView.swift
//  PillCounter
//
//  Created by HC on 31/10/25.
//

import SwiftUI

struct BaseView<TopContent: View, BottomContent: View, HeaderActions: View>: View {

    // MARK: - STORED CONTENT CLOSURES
    let topRatio: CGFloat
    let topContent: () -> TopContent
    let bottomContent: () -> BottomContent
    let headerActions: () -> HeaderActions

    // MARK: - CONFIGURATION PROPERTIES
    let showBackButton: Bool
    let showHamburgerMenu: Bool
    let showPmsConnectionButton : Bool
    let pmsConnectionState: PmsConnectionState

    let title: String

    // MARK: - CONFIRMATION PROPERTIES
    let confirmBack: Bool
    let confirmTitle: String?
    let confirmMessage: String?
    let cancelButtonText: String?
    let confirmButtonText: String?
    
    // MARK: - OPTIONAL BACKGROUND STYLES
    let backButtonBackground: Color?
    let headerActionsBackground: Color?
    let backgroundColor: Color?
    
    let allowKeyboardResize: Bool
    
    let onBack: (() -> Void)?

    // MARK: - ENVIRONMENT
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var confirmationDialogueManager: ConfirmationDialogueManager
    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors
    
    // MARK: - STATE
    @State private var keyboardHeight: CGFloat = 0
    @State private var animatePulse = false
    
    


    // MARK: - MAIN INIT
    init( 
        topRatio: CGFloat = 0.5,
        @ViewBuilder topContent: @escaping () -> TopContent,
        @ViewBuilder bottomContent: @escaping () -> BottomContent,
        @ViewBuilder headerActions: @escaping () -> HeaderActions,
        showBackButton: Bool = false,
        showHamburgerMenu: Bool = false,
        showpmsConnectionButton: Bool = false,
        pmsConnectionState: PmsConnectionState = .disconnected,
        title: String = "",
        confirmBack: Bool = false,
        confirmTitle: String? = nil,
        confirmMessage: String? = nil,
        cancelButtonText: String? = nil,
        confirmButtonText: String? = nil,
        backButtonBackground: Color? = nil,
        headerActionsBackground: Color? = nil,
        backgroundColor: Color? = nil,
        allowKeyboardResize: Bool = false,  // Added for barcodescan view bottom content
        onBack: (() -> Void)? = nil
    ) {
        self.topRatio = topRatio
        self.topContent = topContent
        self.bottomContent = bottomContent
        self.headerActions = headerActions
        self.showBackButton = showBackButton
        self.showHamburgerMenu = showHamburgerMenu
        self.showPmsConnectionButton = showpmsConnectionButton
        self.pmsConnectionState = pmsConnectionState
        self.title = title
        self.confirmBack = confirmBack
        self.confirmTitle = confirmTitle
        self.confirmMessage = confirmMessage
        self.cancelButtonText = cancelButtonText
        self.confirmButtonText = confirmButtonText
        self.backButtonBackground = backButtonBackground
        self.headerActionsBackground = headerActionsBackground
        self.backgroundColor = backgroundColor
        self.allowKeyboardResize = allowKeyboardResize
        self.onBack = onBack
    }

    // MARK: - BODY
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. ADAPTIVE LAYOUT (Handles Orientation)
                adaptiveLayout(geometry: geometry)

                // 2. OVERLAY CONTROLS (Back Button / Hamburger / Header Actions)
                overlayControls(using: geometry)

                // 3. GLOBAL CONFIRMATION POPUP
                if confirmBack, confirmationDialogueManager.isShowing {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Optional: Close on tap outside
                        }

                    confirmationDialogueManager.popupView
                        .padding()
                        .transition(.scale)
                        .zIndex(100)
                }
            }
            
        }
        
        .background(backgroundColor ?? appColors.secondaryBackground)
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(
            UIDevice.current.userInterfaceIdiom == .phone
            ? .all
            : [],
            edges: [.leading, .trailing, .bottom]
        )
        .environment(\.dynamicTypeSize, .medium)
    }
}

// MARK: - CONVENIENCE EXTENSION
extension BaseView where HeaderActions == EmptyView {
    init(
        topRatio: CGFloat = 0.5,
        @ViewBuilder topContent: @escaping () -> TopContent,
        @ViewBuilder bottomContent: @escaping () -> BottomContent,
        showBackButton: Bool = false,
        showHamburgerMenu: Bool = false,
        showPmsConnectionButton: Bool = false,
        pmsConnectionState:PmsConnectionState = .notAvailable,
        title: String = "",
        confirmBack: Bool = false,
        confirmTitle: String? = nil,
        confirmMessage: String? = nil,
        cancelButtonText: String? = nil,
        confirmButtonText: String? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.init(
            topRatio: topRatio,
            topContent: topContent,
            bottomContent: bottomContent,
            headerActions: { EmptyView() },
            showBackButton: showBackButton,
            showHamburgerMenu: showHamburgerMenu,
            showpmsConnectionButton: showPmsConnectionButton,
            pmsConnectionState: pmsConnectionState,
            title: title,
            confirmBack: confirmBack,
            confirmTitle: confirmTitle,
            confirmMessage: confirmMessage,
            cancelButtonText: cancelButtonText,
            confirmButtonText: confirmButtonText,
            onBack: onBack
        )
    }
}

// MARK: - LAYOUT BUILDERS
extension BaseView {

    @ViewBuilder
    private func adaptiveLayout(geometry: GeometryProxy) -> some View {
        let size = geometry.size

        let layout =
            isLandscape
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))

        layout {
            topContent()
                .frame(
                    width: isLandscape ? size.width * topRatio : size.width,
                    height: isLandscape ? size.height : size.height * topRatio
                )
                .clipped()
            if allowKeyboardResize {
                bottomContent()
                    .frame(
                        width: isLandscape
                            ? size.width * (1 - topRatio)
                            : size.width
                    )
                    .frame(maxHeight: .infinity)
            } else {
                bottomContent()
                    .frame(
                        width: isLandscape
                            ? size.width * (1 - topRatio)
                            : size.width,
                        height: isLandscape
                            ? size.height
                            : size.height * (1 - topRatio)
                    )
            }
        }
    }

    @ViewBuilder
    private func overlayControls(
        using geometry: GeometryProxy,
        showBackground: Bool = false
    ) -> some View {
        ZStack {
            if showBackground {
                Rectangle()
                    .fill(appColors.primaryBackground)
                    .ignoresSafeArea(edges: .top)
                    .frame(height: isLandscape ? 44 : 100)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            
            ZStack {
                // 1. LEFT SIDE: Back Button
                if showBackButton {
                    HStack {
                        backButton
                    }
                  
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                }
                
                
                if showPmsConnectionButton {
                    HStack {
                        PMSConnectionButtonView(pmsConnectionState: pmsConnectionState)
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                // 2. RIGHT SIDE: Header Actions + Hamburger
                HStack(spacing: 16) {
                    headerActions()
                    if showHamburgerMenu {
                        hamburgerMenuButton
                    }
                }
                .frame(height: 52)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
            }
        }
    }
}

// MARK: - COMPONENT BUILDERS
extension BaseView {
    
    private var backButton: some View {
        Button {
            handleBackAction()
        } label: {
            HStack {
                PillCountingIconView(
                    imageName: "back_icon",
                    size: 24,
                    padding: 12,
                    foregroundColor: appColors.primary,
                    backgroundColor: backButtonBackground ?? Color.clear,
                    scaleOnIpad: true
                )
                Text((title.count > 25 ? "\(title.prefix(25))..." : title).uppercased())
                    .foregroundStyle(appColors.text)
                    .font(.headline)
            }
        }
    }

    private func handleBackAction() {
        let backAction = onBack ?? {
            router.navigateBack()
        }
        
        if confirmBack {
            confirmationDialogueManager.showConfirmation {
                confirmationPopup
            } onConfirm: {
                backAction()
            }
        } else {
            backAction()
        }
    }


    private var confirmationPopup: some View {
        ConfirmationDialogue(
            title: confirmTitle ?? L10n.Common.confirmation,
            message: confirmMessage ?? L10n.Common.areYouSureGoBack,
            cancelButtonText: cancelButtonText ?? L10n.Common.no,
            confirmButtonText: confirmButtonText ?? L10n.Common.yes
        ) {
            confirmationDialogueManager.hide()
        } onConfirm: {
            confirmationDialogueManager.confirm()
        }
    }

  

    private var hamburgerMenuButton: some View {
        Button {
            router.navigate(to: .authentication(.user(.hamburgerMenu)))
        } label: {
            PillCountingIconView(
                imageName: "hamburger_menu",
                size: 28,
                padding: 12,
                foregroundColor: appColors.primary,
                backgroundColor: .clear,
                scaleOnIpad: true
            )
        }
        .transition(.opacity)
    }
    
//    
//    private var pmsConnectionStatusButton: some View {
//        Button {
//            // action
//        } label: {
//            Image("pms_icon")
//                .font(.system(size: 2, weight: .bold))
//        }
//    }
    var pmsConnectionStatusButton: some View {
        Button {
            // optional action
        } label: {
            Image("pms_icon")
                .renderingMode(.template)
                .foregroundColor(pmsIconColor)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .scaleEffect(
                    pmsConnectionState == .connecting
                    ? (animatePulse ? 1.15 : 1.0)
                    : 1.0
                )
                .onAppear {
                    if pmsConnectionState == .connecting {
                        startPulse()
                    }
                }
                .onChange(of: pmsConnectionState) { _, newValue in
                    if newValue == .connecting {
                        startPulse()
                    } else {
                        animatePulse = false
                    }
                }
        }
        .buttonStyle(.plain)
    }
    
    private func startPulse() {
        withAnimation(
            .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true)
        ) {
            animatePulse = true
        }
    }


    private var pmsIconColor: Color {
        switch pmsConnectionState {
        case .connected:
            return appColors.secondary
            
        case .disconnected:
            return .gray
            
        case .connecting:
            return appColors.secondary
            
        case .notAvailable:
            return .gray
        }
    }

    private func hamburgerMenu(in geometry: GeometryProxy) -> some View {
        hamburgerMenuButton
    }
}


// PMS Connection View in DashBoard
struct PMSConnectionButtonView: View {

    // MARK: - Input
    let pmsConnectionState: PmsConnectionState

    // MARK: - Private State
    @State private var animateScale: Bool = false

    // MARK: - Computed
    private var statusText: String {
        switch pmsConnectionState {
        case .connected:               return L10n.PMS.connected
        case .disconnected, .notAvailable: return L10n.PMS.disconnected
        case .connecting:              return L10n.PMS.connecting
        }
    }

    private var statusColor: Color {
        switch pmsConnectionState {
        case .connected: return AppColors.shared.secondary
        default:         return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.white)
        .clipShape(Capsule())
        .scaleEffect(animateScale ? 1.12 : 1.0)
        .onChange(of: pmsConnectionState) { _, newValue in
            guard newValue == .connected else {
                animateScale = false
                return
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                animateScale = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    animateScale = false
                }
            }
        }
    }
}
