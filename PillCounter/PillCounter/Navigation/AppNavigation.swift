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
    
    @State private var isLandscape: Bool = {
        let o = UIDevice.current.orientation
        if o.isValidInterfaceOrientation { return o.isLandscape }
        return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }()
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
                        
                    case .authentication(.login(.dashboard(.pillCount(.barcodeScanning(let scanType))))):
                        QRBarcodeScannerView(currentScanType: scanType)
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(
                        .login(.dashboard(.pillCount(.pillCountView)))):
                        OPillCountView()
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(.user(.hamburgerMenu)):
                        HamburgerMenuView()
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(.user(.userSettings(.unsyncedTransaction))):
                        UnsyncedTransactionView()
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(.user(.userSettings(.profile))):
                        UserProfileScreen()
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(.user(.userSettings(.settings))):
                        UserSettingsView()
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(.user(.userSettings(.History(let filterType)))):
                        UserHistoryView(filterType: filterType)
                            .navigationBarBackButtonHidden(true)
                        
                        // before navigating to this screen make sure to set the current transaction of the pill scan view model to the selected transaction.
                    case .authentication(
                        .user(.userSettings(.HistoryTransactionDetail))):
                        HistoryTransactionDetailView()
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(
                        .login(.dashboard(.pillCount(.controlledDrug(.vialCount))))):
                        VialCaptureView()
                            .navigationBarBackButtonHidden(true)
                        
                    // MARK: STOCK COUNT
                    case .authentication(
                        .login(.dashboard(.pillCount(.stockCount(.stockCountBatchDetail))))
                    ):
                        StockCountBatchDetail()
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(
                        .login(.dashboard(.pillCount(.stockCount(.stockCountPartialBatchListScreen))))
                    ):
                        StockCountPartialBatchListScreen()
                            .navigationBarBackButtonHidden(true)
                        
                    case .authentication(
                        .login(.dashboard(.pillCount(.stockCount(.stockCountPendingBatchListScreen))))
                    ):
                        StockCountRequestedList()
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
