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
                //MARK: LOGIN
                case .authentication(.login(.LoginEmail)):
                    LoginEmailView()
                        .navigationBarBackButtonHidden(true)
                    
                case .authentication(.login(.otpVerificationLogin)):
                    LoginOtpVerificationView()
                        .navigationBarBackButtonHidden(true)
                //MARK: DASHBORD
                case .authentication(.login(.dashboard(.dashboardHome))):
                    DashboardView()
                        .navigationBarBackButtonHidden(true)
                    
                case .authentication(.login(.dashboard(.fixedCountPartial))):
                    DispenseCountPartialTxnList(title: "pending dispense counts")
                        .navigationBarBackButtonHidden(true)
                    
                    
                case .authentication(.login(.dashboard(.pillCount(.barcodeScanning(let scanType))))):
                    QRBarcodeScannerView(currentScanType: scanType)
                        .navigationBarBackButtonHidden(true)
                    
                case .authentication(
                    .login(.dashboard(.pillCount(.pillCountView)))):
                    OPillCountView()
                        .navigationBarBackButtonHidden(true)
                    
                case .authentication(
                    .login(.dashboard(.pillCount(.pillCountHistoryView)))):
                    PillScanDetailGridScreen()
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
                 
                //MARK: HISTORY
                case .authentication(.user(.userSettings(.History(let filterType)))):
                    UserHistoryView(filterType: filterType)
                        .navigationBarBackButtonHidden(true)
                    
                case .authentication(
                    .user(.userSettings(.HistoryTransactionDetail))):
                    HistoryTransactionDetailView()
                        .navigationBarBackButtonHidden(true)

                case .authentication(
                    .user(.userSettings(.HistoryBatchDetail))):
                    HistoryBatchDetailView()
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
                }
            }
        }
        .environment(\.isLandscape, isLandscape)
        .ignoresSafeArea()
        .ignoresSafeArea()
              .onReceive(
                  NotificationCenter.default.publisher(
                      for: UIDevice.orientationDidChangeNotification
                  )
              ) { _ in
                  let o = UIDevice.current.orientation
                  guard o.isValidInterfaceOrientation else { return }
                  let newValue = o.isLandscape
                  if isLandscape != newValue {
                      isLandscape = newValue
                  }
              }
        .onAppear {
            appColors.updateSystemAppearance(colorScheme == .dark)
        }
        .onChange(of: colorScheme) { _, newValue in
            appColors.updateSystemAppearance(newValue == .dark)
        }
        
    }
}


