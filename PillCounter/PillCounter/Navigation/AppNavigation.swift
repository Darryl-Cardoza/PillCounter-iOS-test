//
//  AppNavigation.swift
//  PillCounter
//
//  Created by HC on 31/10/25.
//

import SwiftUI

struct AppNavigation: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var loginViewModel: LoginViewModel
    @EnvironmentObject private var appColors: AppColors
    @Environment(\.colorScheme) private var colorScheme

    @State private var isLandscape: Bool = {
        let o = UIDevice.current.orientation
        if o.isValidInterfaceOrientation { return o.isLandscape }
        return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }()

    var body: some View {
        NavigationStack(path: $router.navigationPath) {
            Group {
                if AppStorageManager.shared.isLoggedIn {
                    DashboardView()
                } else {
                    LoginEmailView()
//                    DashboardView()
                }
            }
            .navigationDestination(for: PillCounterFlow.self) { destination in
                switch destination {
                // MARK: LOGIN
                case .authentication(.login(.LoginEmail)):
                    LoginEmailView()
                        .navigationBarBackButtonHidden(true)

                case .authentication(.login(.otpVerificationLogin)):
                    LoginOtpVerificationView()
                        .navigationBarBackButtonHidden(true)

                // MARK: DASHBOARD
                case .authentication(.login(.dashboard(.dashboardHome))):
                    DashboardView()
                        .navigationBarBackButtonHidden(true)

                case .authentication(.login(.dashboard(.fixedCountPartial))):
                    DispenseCountPartialTxnList(title: "pending dispense counts")
                        .navigationBarBackButtonHidden(true)
                    
                    
                case .authentication(.login(.dashboard(.pillCount(.scan(let scanType, let txnId, let batchId, let bucketId))))):
                    UnifiedCameraView(
                        currentScanType: scanType,
                        dispenseTxnId: txnId,
                        stockBatchId: batchId,
                        newBatchBucketId: bucketId
                    )
                    .navigationBarBackButtonHidden(true)

                case .authentication(.user(.hamburgerMenu)):
                    HamburgerMenuView()
                        .navigationBarBackButtonHidden(true)

                case .authentication(.user(.userSettings(.unsyncedTransaction))):
                    UnsyncedTransactionView()
                        .navigationBarBackButtonHidden(true)

                case .authentication(.user(.userSettings(.profile(let mustSelectTerminal)))):
                    UserProfileScreen(mustSelectTerminal: mustSelectTerminal)
                        .navigationBarBackButtonHidden(true)

                case .authentication(.user(.userSettings(.settings))):
                    UserSettingsView()
                        .navigationBarBackButtonHidden(true)

                case .authentication(.user(.userSettings(.quickAccessUsers))):
                    QuickAccessUsersView()
                        .navigationBarBackButtonHidden(true)

                // MARK: HISTORY
                case .authentication(.user(.userSettings(.History(let filterType, let statusFilter)))):
                    UserHistoryView(filterType: filterType, stautsType: statusFilter)
                        .navigationBarBackButtonHidden(true)

                case .authentication(.user(.userSettings(.HistoryTransactionDetail(let txnId)))):
                    HistoryTransactionDetailView(txnId: txnId)
                        .navigationBarBackButtonHidden(true)

                case .authentication(.user(.userSettings(.HistoryBatchDetail(let batchId)))):
                    HistoryBatchDetailView(batchId: batchId)
                        .navigationBarBackButtonHidden(true)

                }
            }
        }
        .environment(\.isLandscape, isLandscape)
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
        .onChange(of: colorScheme) { _, newScheme in
            appColors.updateSystemAppearance(newScheme == .dark)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            appColors.updateSystemAppearance(colorScheme == .dark)
        }
    }
}
