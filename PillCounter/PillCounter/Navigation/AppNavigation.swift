//
//  AppNavigation.swift
//  PillCounter
//
//  Created by HC on 31/10/25.
//

import SwiftUI

struct AppNavigation: View {
    @EnvironmentObject private var router: Router
    @AppStorage(AppStorageManager.AppStorageKeys.isLoggedIn) var isLoggedIn:
        Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            NavigationStack(path: $router.navigationPath) {
                Group {
                    if isLoggedIn {
                        DashboardView()
                    } else {
                        LoginEmailView()
                    }
                }
                .navigationDestination(for: PillCounterFlow.self) {
                    destination in
                    switch destination {
                    case .authentication(.login(.LoginEmail)):
                        LoginEmailView()
                            .navigationBarBackButtonHidden(true)

                    case .authentication(.login(.otpVerificationLogin)):
                        LoginOtpVerificationView()
                            .navigationBarBackButtonHidden(true)

                    case .authentication(.login(.dashboard(.dashboardHome))):
                        DashboardView()
                            .navigationBarBackButtonHidden(true)

                    case .authentication(.login(.dashboard(.fixedCountPartial))):
                        CountHistoryView(title: "pending dispense counts")
                            .navigationBarBackButtonHidden(true)

                    case .authentication(
                        .login(.dashboard(.regularCountPartial))):
                        CountHistoryView(title: "pending quick counts")
                            .navigationBarBackButtonHidden(true)

                    case .authentication(
                        .login(.dashboard(.pillCount(.barcodeScanning)))):
                        QRBarcodeScannerView()
                            .navigationBarBackButtonHidden(true)

                    case .authentication(
                        .login(.dashboard(.pillCount(.pillCountView)))):
                        OPillCountView()
                            .navigationBarBackButtonHidden(true)

                    case .authentication(.user(.hamburgerMenu)):
                        HamburgerMenuView()
                            .navigationBarBackButtonHidden(true)

                    case .authentication(.user(.userSettings(.profile))):
                        UserProfileScreen()
                            .navigationBarBackButtonHidden(true)

                    case .authentication(.user(.userSettings(.settings))):
                        UserSettingsView()
                            .navigationBarBackButtonHidden(true)

                    case .authentication(.user(.userSettings(.History))):
                        UserHistoryView()
                            .navigationBarBackButtonHidden(true)

                    // before navigating to this screen make sure to set the current transaction of the pill scan view model to the selected transaction.
                    case .authentication(
                        .user(.userSettings(.HistoryTransactionDetail))):
                        HistoryTransactionDetailView()
                            .navigationBarBackButtonHidden(true)

                    }
                }
            }
            .environment(\.isLandscape, isLandscape)
        }
        .onAppear {
            appColors.updateSystemAppearance(colorScheme == .dark)
        }
        .onChange(of: colorScheme) { _, newValue in
            appColors.updateSystemAppearance(newValue == .dark)
        }
        
    }
}
