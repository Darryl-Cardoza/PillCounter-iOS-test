//
//  DashboardView.swift
//  PillCounter
//
//  Created by HC on 04/11/25.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel
    @State private var someParialValue: Int = 1
    @State private var someParialValue2: Int = 2
    @State private var someCompletedValue: Int = 3
    @State private var someCompletedValue2: Int = 4
    @AppStorage(AppStorageManager.AppStorageKeys.userId) var userId: String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
        Bool = true
    @AppStorage(AppStorageManager.AppStorageKeys.isHl7Enable) var isHl7Enable:
        Bool = false


    
    
    // MARK: - LOCAL STATE
    // This ensures we only redirect once per session (prevents infinite loop on Skip)
    @State private var hasCheckedNewUser: Bool = false
    var body: some View {
        BaseView(
            topRatio: 0.5,
            topContent: {
                GeometryReader { geometry in
                    VStack(spacing: 10) {
                        Spacer()
                        Spacer()
                        VStack(spacing: 15) {
                            
                            Image("fixed_count")
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: geometry.size.width * 0.35,
                                    height: geometry.size.width * 0.35
                                )
                                .overlay {
                                    appColors.secondary
                                        .mask {
                                            Image("fixed_count")
                                                .resizable()
                                                .scaledToFit()
                                        }
                                }
                               
                            Spacer().frame(height: 15)
                            
                            Text("FIXED_COUNT_TITLE")
                                .font(.title)
                                .foregroundStyle(appColors.secondary)
                            
                            Text("FIXED_COUNT_SUBTITLE")
                                .foregroundStyle(appColors.text)
                            
                        }
                        
                        HStack {
                            PillCountingButton(
                                iconName: "tick_icon_pink",
                                title:
                                    "\(userViewModel.fixedCountTransactionCompletedCount) \(NSLocalizedString("COMPLETED", comment: ""))",
                                textColor: appColors.secondary,
                                backgroundColor: appColors.secondaryBackground,
                                action: {
                                    // some action to be performed like opening or navigating
                                    router.navigate(to: .authentication(.user(.userSettings(.History(.fixed)))))
                                },
                                iconColor: appColors.secondary
                            )

                            Spacer()

                            PillCountingButton(
                                iconName: "partial",
                                title:
                                    "\(userViewModel.fixedCountTransactionPartialCount) \(NSLocalizedString("PARTIAL", comment: ""))",
                                textColor: appColors.secondary,
                                backgroundColor: appColors.primaryBackground,
                                action: {
                                    // some action to be performed like opening or navigatin
                                        router.selectedPillScanningType = .FIXED
                                        
                                        router.navigate(
                                            to: .authentication(
                                                .login(
                                                    .dashboard(.fixedCountPartial)))
                                        )
                                },
                                iconColor: appColors.secondary
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)

                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appColors.secondaryBackground)
                    .onTapGesture {
                        
                        // before navigating to the barcode scanning set the router value to fixed because we will need this value ahead for creating transactions.
                        router.selectedPillScanningType = .FIXED
                        
                        router.navigate(
                            to: .authentication(
                                .login(
                                    .dashboard(
                                        .pillCount(.barcodeScanning)))))
                    }
                
                }

            },
            bottomContent: {
                GeometryReader { geometry in
                    VStack(spacing: 10) {
                        Spacer()
                        Spacer()
                        Image("regular_count")
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: geometry.size.width * 0.35,
                                height: geometry.size.width * 0.35
                            )
                            .overlay {
                                appColors.primary
                                    .mask {
                                        Image("regular_count")
                                            .resizable()
                                            .scaledToFit()
                                    }
                            }
                        

                        Spacer().frame(height: 15)

                        Text("REGULAR_COUNT_TITLE")
                            .font(.title)
                            .foregroundStyle(appColors.primary)

                        Text("REGULAR_COUNT_SUBTITLE")
                            .foregroundStyle(appColors.text)

                        Spacer()

                        HStack {
                            PillCountingButton(
                                iconName: "tick_icon_pink",
                                title:
                                    "\(userViewModel.regularCountTransactionCompletedCount) \(NSLocalizedString("COMPLETED", comment: ""))",
                                textColor: appColors.text,
                                backgroundColor: appColors.primaryBackground,
                                action: {
                                    // some action to be performed like opening or navigating
                                    router.navigate(to: .authentication(.user(.userSettings(.History(.regular)))))
                                },
                                iconColor: appColors.primary
                            )
                            Spacer()

                            PillCountingButton(
                                iconName: "partial",
                                title:
                                    "\(userViewModel.regularCountTransactionPartialCount) \(NSLocalizedString("PARTIAL", comment: ""))",
                                textColor: appColors.text,
                                backgroundColor: appColors.secondaryBackground,
                                action: {
                                    // some action to be performed like opening or navigating
                                    // need to set this as regular.
                                        router.selectedPillScanningType = .REGULAR
                                        
                                        router.navigate(
                                            to: .authentication(
                                                .login(
                                                    .dashboard(.regularCountPartial)
                                                )))
                                    
                                },
                                iconColor: appColors.primary
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)

                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appColors.primaryBackground)
                    .cornerRadius(24)
                    .onTapGesture {
                        // routing for regular count
                        // make sure before you route we set the
                        // router.selectedPillScanningType to regular.

                        router.selectedPillScanningType = .REGULAR

                        router.navigate(
                            to: .authentication(
                                .login(
                                    .dashboard(
                                        .pillCount(.barcodeScanning)))))
                    }
                }
            },
            showBackButton: false,
            showHamburgerMenu: true,
            showPmsConnectionButton: isHl7Enable,
            pmsConnectionState : userViewModel.pmsConnectionState
  

        )
        .onAppear {
    
            Task(priority: .background) {
                await userViewModel.checkAndRefreshTokenIfNeeded()
            }
            
            // MARK: - NEW USER REDIRECT LOGIC
            if isNewUser && !hasCheckedNewUser {
                hasCheckedNewUser = true
                router.navigate(
                    to: .authentication(.user(.userSettings(.profile))))
            } else {
                // Only fetch user details if we are staying on Dashboard
                Task {
                    await userViewModel.getUser()
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
