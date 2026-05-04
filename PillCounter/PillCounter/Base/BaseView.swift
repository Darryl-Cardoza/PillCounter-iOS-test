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
    let showBackBackground: Bool
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
        showBackBackground: Bool = false,
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
        allowKeyboardResize: Bool = false,  // Added for barcodescan view bottom content
        onBack: (() -> Void)? = nil
    ) {
        self.topRatio = topRatio
        self.topContent = topContent
        self.bottomContent = bottomContent
        self.headerActions = headerActions
        self.showBackButton = showBackButton
        self.showBackBackground = showBackBackground
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
        
        .background(appColors.secondaryBackground)
        .ignoresSafeArea(
            allowKeyboardResize ?
            .container :
            .all,
            edges: allowKeyboardResize ? [.top, .leading, .trailing] : .all
        )
        .ignoresSafeArea(edges: .bottom)
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
                    //                .padding(.leading, 8)
                    .padding(
                        .top,
                        isLandscape
                        ? geometry.safeAreaInsets.top + 10
                        : max(geometry.safeAreaInsets.top + 10, 40)
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                }
                
                
                if showPmsConnectionButton {
                    HStack {
                        pmsConnectionStatusButton
                            .scaleEffect(1)
                            .padding(8)
                    }
                    .padding(
                        .top,
                        isLandscape
                        ? 0
                        : max(geometry.safeAreaInsets.top + 10, 40)
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                }
                
                
                
                // 2. RIGHT SIDE: Header Actions + Hamburger
                HStack(spacing: 16) {
                    // Inject the custom actions here
                    headerActions()
                        .padding(.top, isLandscape ? 20 : 0)
                    
                    if showHamburgerMenu {
                        hamburgerMenuButton
                    }
                }
                //            .padding(.trailing, 8)
                // FIX: Force height to 52 to match the Left Side Back Button (28px + 12px padding * 2)
                // This ensures vertical centering aligns perfectly
                .frame(height: 52)
                .padding(
                    .top,
                    isLandscape
                    ? 0
                    : max(geometry.safeAreaInsets.top + 10, 40)
                )
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
                Image("back_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .padding(12)
                    .background(
                        backButtonBackground ?? Color.clear
                    )
                    .clipShape(Circle())

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
            title: confirmTitle ?? "Confirmation",
            message: confirmMessage ?? "Are you sure you want to go back?",
            cancelButtonText: cancelButtonText ?? "NO",
            confirmButtonText: confirmButtonText ?? "YES"
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
            Image("hamburger_menu")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .padding(12)
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


