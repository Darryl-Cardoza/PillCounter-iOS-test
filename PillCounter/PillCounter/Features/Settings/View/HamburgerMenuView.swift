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
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    // Single settings view model drives the menu's settings-derived rows:
    // the unsynced count and the save-history display.
    @StateObject private var settingsViewModel = SettingsViewModel()

    @State private var showLogoutPopup: Bool = false
    @State private var showStockCountPopup: Bool = false
    @State private var showSelectBucketIdPopup: Bool = false
    @State private var selectedStockCountOption: StockCountOption = .newBatch

    private let menuItems = HamburgerMenuItem.allCases

    private var isPmsIntegrated: Bool { AppStorageManager.shared.isPmsIntegrated }

    /// Unsynced transactions are a PMS-integration-only concept — disable the row
    /// when PMS integration is off for this account.
    private func isItemDisabled(_ item: HamburgerMenuItem) -> Bool {
        item == .UnsyncedTransaction && !isPmsIntegrated
    }

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
                showHamburgerMenu: false,
                title: ""
            )
        }
        .customPopup(isPresented: $showLogoutPopup) {
            logoutPopUp
        }
        .customPopup(isPresented: $showStockCountPopup) {
            stockCountPopUp
        }
        .customPopup(isPresented: $showSelectBucketIdPopup) {
            selectBucketPopUp
        }
        .onAppear {
            Task {
                userViewModel.getAllTransactionsAndFilterByCountType()
            }
        }
    }
      

    // MARK: - LOGOUT POP UP
    private var logoutPopUp: some View {
        ConfirmationDialogue(
            title: L10n.Menu.confirmLogoutTitle,
            message: L10n.Menu.confirmLogoutMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Menu.logoutButton
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
                        Divider()
                            .overlay(appColors.primaryBackground)
                            .padding(.horizontal, 20)
                        
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .padding(.top, 64)
        .padding(
            .horizontal,
            isLandscape ? SafeAreaInsets.leading : 0
        )
    }

    // MARK: - MENU ROW BUILDER
    @ViewBuilder
    private func menuRow(for item: HamburgerMenuItem, index: Int) -> some View {
        let color: Color =
            index.isMultiple(of: 2) ? appColors.primary : appColors.primary
        let monthDuration: Int = 3

        // Logic: Is this a "complex" row with buttons?
//        let isCountItem = (item == .FixedCount || item == .RegularCount)
        let isCountItem = false

        let disabled = isItemDisabled(item)

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
                        .fontWeight(.regular)

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
                    ).padding(.top, 20)
                }
            }
            // UNIFIED PADDING: Ensures exact same spacing for every item type
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Grayed out when PMS is off, but kept tappable so the tap can surface
        // the "feature not available" toast (handled in handleMenuSelection).
        .opacity(disabled ? 0.6 : 1.0)
    }

    // MARK: - TRAILING VIEW BUILDER
    @ViewBuilder
    private func trailingView(
        for item: HamburgerMenuItem, isLandscape: Bool, monthDuration: Int
    ) -> some View {
        switch item {
            
        case .History:
            Text(settingsViewModel.saveHistoryDisplayText)
                .foregroundStyle(appColors.secondary)
                .padding(.horizontal, isLandscape ? 10 : 0)

        case .UnsyncedTransaction:
            Text("\(settingsViewModel.unsyncedCount)")
                .foregroundStyle(appColors.secondary)
                .padding(.horizontal, isLandscape ? 10 : 0)
              
//        case .FixedCount:
//            countButtonsRow(
//                completedCount: userViewModel.fixedCountTransactionCompletedCount,
//                partialCount: userViewModel.fixedCountTransactionPartialCount,
//                completedColor: appColors.primary,
//                partialColor: appColors.primary,
//                completedBg: appColors.primaryBackground,
//                partialBg: appColors.primaryBackground,
//                primaryIconColor: appColors.primary,
//                isLandscape: isLandscape,
//                isFixed: true,
//                onPartialTap: {
//                        router.selectedPillScanningType = .FIXED
//                        router.navigate(
//                            to: .authentication(
//                                .login(.dashboard(.fixedCountPartial))))
//                }
//            ).padding(.horizontal,0)
//
//        case .RegularCount:
//            countButtonsRow(
//                completedCount: stockCountViewModel.totalCompletedBatchCount,
//                partialCount:stockCountViewModel.totalBatchCount,
//                completedColor: appColors.primary,
//                partialColor: appColors.primary,
//                completedBg: appColors.primaryBackground,
//                partialBg: appColors.primaryBackground,
//                primaryIconColor: appColors.primary,
//                isLandscape: isLandscape,
//                isFixed: false,
//                onPartialTap: {
//                        router.selectedPillScanningType = .REGULAR
//                        router.navigate(
//                            to: .authentication(
//                                .login(.dashboard(.pillCount(.stockCount(.stockCountPartialBatchListScreen))))))
//                }
//            )

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
                iconName: "check_with_circle",
                title:
                    "\(completedCount) \(L10n.Dashboard.completed)",
                textColor: completedColor,
                backgroundColor: completedBg,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 32,
                horizontalPadding: 0,
                verticalPadding: 8,
                iconSize: 16,
                action: {
                    router.navigate(to: .authentication(.user(.userSettings(.History(historyType, .completed)))))
                },
                iconColor: primaryIconColor
            )
            .frame(maxWidth:150)

            if !isLandscape {Spacer()}
            
            PillCountingButton(
                iconName: "partial",
                title:
                    "\(partialCount) \(L10n.Dashboard.pending)",
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

    // MARK: - STOCK COUNT POPUP
    private var stockCountPopUp: some View {
        VStack(spacing: 35) {
            VStack(alignment: .leading) {
                Text(L10n.Dashboard.Popup.whatWouldYouDo)
                    .font(.system(size: 16))
                    .fontWeight(.semibold)
                    .foregroundStyle(appColors.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 28) {
                PillCountingRadioButton(
                    option: StockCountOption.newBatch,
                    selectedOption: $selectedStockCountOption,
                    label: L10n.Dashboard.Popup.createNewBatch,
                    selectedColor: appColors.secondary,
                    unselectedColor: .gray,
                    size: 20,
                    lineWidth: 2,
                    textColor: appColors.text
                )
                PillCountingRadioButton(
                    option: StockCountOption.existingBatch,
                    selectedOption: $selectedStockCountOption,
                    label: L10n.Dashboard.Popup.continueLastBatch,
                    selectedColor: appColors.secondary,
                    unselectedColor: .gray,
                    size: 20,
                    lineWidth: 2,
                    textColor: appColors.text
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            EqualWidthHStackButtons(spacing: 20) {
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.cancel,
                    textColor: appColors.text,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: { showStockCountPopup = false }
                )
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.ok,
                    textColor: Color.white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        switch selectedStockCountOption {
                        case .newBatch:
                            let buckets = userViewModel.bucket
                            pillScanViewModel.bucketOptions = buckets
                            pillScanViewModel.selectedBucket = buckets.first ?? ""
                            showSelectBucketIdPopup = true
                            showStockCountPopup = false
                        case .existingBatch:
                            if stockCountViewModel.continueLastBatch() {
                                router.navigate(to: .authentication(.login(.dashboard(.pillCount(.scan(.stockCount))))))
                            } else {
                                pillScanViewModel.showToastMessage(text: L10n.Menu.noLastBatchFound)
                            }
                            showStockCountPopup = false
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    // MARK: - SELECT BUCKET POPUP
    private var selectBucketPopUp: some View {
        VStack(spacing: 35) {
            VStack(alignment: .leading) {
                Text(L10n.Dashboard.Popup.selectBucket)
                    .font(.system(size: 16))
                    .fontWeight(.semibold)
                    .foregroundStyle(appColors.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 28) {
                ForEach(pillScanViewModel.bucketOptions, id: \.self) { bucket in
                    PillCountingRadioButton(
                        option: bucket,
                        selectedOption: $pillScanViewModel.selectedBucket,
                        label: bucket,
                        selectedColor: appColors.secondary,
                        unselectedColor: .gray,
                        size: 20,
                        lineWidth: 2,
                        textColor: appColors.text
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            EqualWidthHStackButtons(spacing: 20) {
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.cancel,
                    textColor: appColors.text,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: { showSelectBucketIdPopup = false }
                )
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.ok,
                    textColor: Color.white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        stockCountViewModel.createNewBatch(bucketId: pillScanViewModel.selectedBucket)
                        router.navigate(to: .authentication(.login(.dashboard(.pillCount(.scan(.stockCount))))))
                        showSelectBucketIdPopup = false
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - MENU ACTION HANDLER
    private func handleMenuSelection(_ item: HamburgerMenuItem) {
        switch item {
//        case .FixedCount:
//            router.selectedPillScanningType = .FIXED
//            router.navigate(
//                to: .authentication(
//                    .login(.dashboard(.pillCount(.scan(.rx_label))))))
//            
        case .UnsyncedTransaction:
            // PMS off → unsynced transactions are unavailable; surface a toast
            // instead of navigating.
            if isItemDisabled(.UnsyncedTransaction) {
                ToastManager.shared.show(message: L10n.Menu.featureNotAvailableMessage)
                return
            }
            router.navigate(
                to: .authentication(.user(.userSettings(.unsyncedTransaction))))

        case .Settings:
            router.navigate(
                to: .authentication(.user(.userSettings(.settings))))

//        case .RegularCount:
//            router.selectedPillScanningType = .REGULAR
//            showStockCountPopup = true
//            selectedStockCountOption = .newBatch

        case .Logout:
            Task {
                showLogoutPopup = true
            }

        case .Profile:
            router.navigate(to: .authentication(.user(.userSettings(.profile(mustSelectTerminal: false)))))

        case .History:
            router.navigate(to: .authentication(.user(.userSettings(.History(.fixed, .all)))))

        }
    }
}

#Preview(traits: .landscapeRight) {
    HamburgerMenuView()
        .environmentObject(Router())
}
