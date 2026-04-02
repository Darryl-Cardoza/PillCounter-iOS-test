//
//  HamburgerMenuView.swift
//  PillCounter
//
//  Created by HC on 04/11/25.
//

import SwiftUI

struct HamburgerMenuView: View {
    
    // MARK: - PROPERTIES
    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var loginViewModel: LoginViewModel
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel

    @State private var showLogoutPopup: Bool = false
    
    @AppStorage(AppStorageManager.AppStorageKeys.saveHistoryOption)
    

    
    private var storedHistoryOption: String = SaveHistoryOption.default.rawValue
    
    private let menuItems = HamburgerMenuItem.allCases

    // MARK: BODY
    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: {
                    menuContent
                },
                bottomContent: {
                    EmptyView()
                },
                headerActions: { EmptyView() },
                showBackButton: true,
                showHamburgerMenu: false
            )
        }
        .customPopup(isPresented: $showLogoutPopup) {
            logoutPopUp
        }
        .onAppear {
            Task {
                await userViewModel.getUnsyncedTransactions()
                userViewModel.getAllTransactionsAndFilterByCountType()
            }
        }
    }
      

    // MARK: - LOGOUT POP UP
    private var logoutPopUp: some View {
        ConfirmationDialogue(
            title: "Confirm Logout",
            message: "Are you sure you want to logout?",
            cancelButtonText: "cancel",
            confirmButtonText: "Logout"
        ) {
            showLogoutPopup = false
        } onConfirm: {
            Task {
                router.setRoot(
                    to: .authentication(.login(.LoginEmail)))
                await loginViewModel.logout()
                
                showLogoutPopup = false
                AppLogoutManager.performLogout(
                    userVM: userViewModel,
                    pillScanVM: pillScanViewModel,
                    loginViewModel: loginViewModel
                )
            }
        }
    }

    // MARK: - MENU CONTENT
    private var menuContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(menuItems.indices, id: \.self) { index in
                    let item = menuItems[index]

                    VStack(spacing: 0) {
                        // 1. The Row Content
                        menuRow(for: item, index: index)

                        // 2. Custom Divider
                        // We add the divider for all except the last item
                        if index < menuItems.count - 1 {
                            Divider()
                                .overlay(appColors.text.opacity(0.2))
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
            // Add global top/bottom padding to the scroll view content
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        // BaseView header offset
        .padding(.top, 80)
        // Safe Area handling for Landscape
        .padding(
            .horizontal,
            isLandscape ? SafeAreaInsets.leading : 0
        )
    }

    // MARK: - MENU ROW BUILDER
    @ViewBuilder
    private func menuRow(for item: HamburgerMenuItem, index: Int) -> some View {
        let color: Color =
            index.isMultiple(of: 2) ? appColors.secondary : appColors.primary
        let monthDuration: Int = 3

        // Logic: Is this a "complex" row with buttons?
        let isCountItem = (item == .FixedCount || item == .RegularCount)

        Button {
            handleMenuSelection(item)
        } label: {
            VStack(alignment: .leading, spacing: 12) {

                // --- ROW TOP: Icon + Title + (Landscape Buttons / Simple Text) ---
                HStack(spacing: 15) {

                    // ICON CONTAINER
                    ZStack {
                        Image(item.iconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .overlay(
                                color.mask(
                                    Image(item.iconName)
                                        .resizable()
                                        .scaledToFit()
                                )
                            )
                    }
                    .frame(width: 40)

                    // TITLE
                    Text(item.title)
                        .foregroundColor(appColors.text)
                        .font(.headline)

                    Spacer()

                    // TRAILING CONTENT
                    // In Landscape: Show everything (Buttons or Text)
                    // In Portrait: ONLY show simple text (like History). Hide Buttons (they go below).
                    if isLandscape || !isCountItem {
                        trailingView(
                            for: item,
                            isLandscape: isLandscape,
                            monthDuration: monthDuration
                        )
                    }
                }

                // --- ROW BOTTOM: Buttons (Portrait Only) ---
                if !isLandscape && isCountItem {
                    trailingView(
                        for: item,
                        isLandscape: isLandscape,
                        monthDuration: monthDuration
                    )
                }
            }
            // UNIFIED PADDING: Ensures exact same spacing for every item type
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - TRAILING VIEW BUILDER
    @ViewBuilder
    private func trailingView(
        for item: HamburgerMenuItem, isLandscape: Bool, monthDuration: Int
    ) -> some View {
        switch item {
        case .History:
            Text("\(storedHistoryOption)")
                .foregroundStyle(appColors.text)
                .padding(.horizontal, isLandscape ? 10 : 0)

        case .UnsyncedTransaction:
            Text("\(userViewModel.unsyncedTransactions.count)")
                .foregroundStyle(appColors.text)
                .padding(.horizontal, isLandscape ? 10 : 0)
              
        case .FixedCount:
            countButtonsRow(
                completedCount: userViewModel
                    .fixedCountTransactionCompletedCount,
                partialCount: userViewModel.fixedCountTransactionPartialCount,
                completedColor: appColors.secondary,
                partialColor: appColors.secondary,
                completedBg: appColors.secondaryBackground,
                partialBg: appColors.primaryBackground,
                primaryIconColor: appColors.secondary,
                isLandscape: isLandscape,
                isFixed: true,
                onPartialTap: {
                        router.selectedPillScanningType = .FIXED
                        router.navigate(
                            to: .authentication(
                                .login(.dashboard(.fixedCountPartial))))
                }
            ).padding(.horizontal,0)

        case .RegularCount:
            countButtonsRow(
                completedCount: userViewModel
                    .regularCountTransactionCompletedCount,
                partialCount: userViewModel.regularCountTransactionPartialCount,
                completedColor: appColors.text,
                partialColor: appColors.text,
                completedBg: appColors.secondaryBackground,
                partialBg: appColors.primaryBackground,
                primaryIconColor: appColors.primary,
                isLandscape: isLandscape,
                isFixed: false,
                onPartialTap: {
                        router.selectedPillScanningType = .REGULAR
                        router.navigate(
                            to: .authentication(
                                .login(.dashboard(.regularCountPartial))))
                }
            )

        default:
            EmptyView()
        }
    }

    // MARK: - BUTTONS ROWS HELPER
    @ViewBuilder
    private func countButtonsRow(
        completedCount: Int,
        partialCount: Int,
        completedColor: Color,
        partialColor: Color,
        completedBg: Color,
        partialBg: Color,
        primaryIconColor: Color,
        isLandscape: Bool,
        isFixed: Bool,
        onPartialTap: @escaping () -> Void
    ) -> some View {
        let historyType: HistoryFilterType = if (isFixed){  .fixed} else{ .regular}
        HStack(spacing: 10) {
            // Landscape: Buttons align Right. Portrait: Buttons fill width.
            if isLandscape { Spacer(minLength: 0) }

            PillCountingButton(
                iconName: "tick_icon_pink",
                title:
                    "\(completedCount) \(NSLocalizedString("COMPLETED", comment: ""))",
                textColor: completedColor,
                backgroundColor: completedBg,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 32,
                horizontalPadding: 0,
                verticalPadding: 0,
                iconSize: 16,
                action: {
                    router.navigate(to: .authentication(.user(.userSettings(.History(historyType)))))
                },
                iconColor: primaryIconColor
            )
            .fixedSize()
            .frame(minWidth: isLandscape ? 150 : nil)

            
            if !isLandscape {Spacer()}
            
            
            PillCountingButton(
                iconName: "partial",
                title:
                    "\(partialCount) \(NSLocalizedString("PARTIAL", comment: ""))",
                textColor: partialColor,
                backgroundColor: partialBg,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 32,
                horizontalPadding:  0,
                verticalPadding: 8,
                iconSize: 16,
                action: onPartialTap,
                iconColor: primaryIconColor
            )
            .frame(maxWidth:150)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - MENU ACTION HANDLER
    private func handleMenuSelection(_ item: HamburgerMenuItem) {
        switch item {
        case .FixedCount:
            router.selectedPillScanningType = .FIXED
            router.navigate(
                to: .authentication(
                    .login(.dashboard(.pillCount(.barcodeScanning)))))
            
        case .UnsyncedTransaction:
            router.navigate(
                to: .authentication(.user(.userSettings(.unsyncedTransaction))))
            
        case .Settings:
            router.navigate(
                to: .authentication(.user(.userSettings(.settings))))

        case .RegularCount:
            router.selectedPillScanningType = .REGULAR
            router.navigate(
                to: .authentication(
                    .login(.dashboard(.pillCount(.barcodeScanning)))))

        case .Logout:
            Task {
                showLogoutPopup = true
            }

        case .Profile:
            router.navigate(to: .authentication(.user(.userSettings(.profile))))

        case .History:
            router.navigate(to: .authentication(.user(.userSettings(.History(.all)))))

        }
    }
}

#Preview(traits: .landscapeRight) {
    HamburgerMenuView()
        .environmentObject(Router())
}
