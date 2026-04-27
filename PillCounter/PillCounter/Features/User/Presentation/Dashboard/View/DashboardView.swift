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
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @StateObject private var locationService = LocationService.shared

    @State private var someParialValue: Int = 1
    @State private var someParialValue2: Int = 2
    @State private var someCompletedValue: Int = 3
    @State private var someCompletedValue2: Int = 4
    @AppStorage(AppStorageManager.AppStorageKeys.userId) var userId: String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
        Bool = true
    @AppStorage(AppStorageManager.AppStorageKeys.isHl7Enable) var isHl7Enable:
        Bool = false

    @State private var showStockCountPopup: Bool = false
    @State private var selectedStockCountOption: StockCountOption = .newBatch
    @State private var showSelectBucketIdPopup : Bool = false
    
    
    // MARK: - LOCAL STATE
    // This ensures we only redirect once per session (prevents infinite loop on Skip)
    @State private var hasCheckedNewUser: Bool = false
    var body: some View {
        ZStack {
            
            BaseView(
                topRatio: 0.5,
                topContent: {
                    GeometryReader { geometry in
                        VStack(spacing: 10) {
                            Spacer()
                            Spacer()
                            Image("dispense_dashboard_icon")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .foregroundColor(appColors.secondary)
                                .padding(40)
                                .background(
                                    ZStack {
                                        Circle()
                                            .stroke(appColors.primary.opacity(0.3), lineWidth: 7)
                                            .blur(radius: 5)
                                        Circle()
                                            .stroke(appColors.primary, lineWidth: 4)
                                    }
                                )
                            
                            Spacer().frame(height: 15)
                            
                            Text("FIXED_COUNT_TITLE")
                                .font(.title)
                                .foregroundStyle(appColors.secondary)
                            
                            Text("FIXED_COUNT_SUBTITLE")
                                .foregroundStyle(appColors.text)
                            Spacer()
                            
                            HStack {
                                PillCountingButton(
                                    iconName: "check_with_circle",
                                    title:
                                        "\(userViewModel.fixedCountTransactionCompletedCount) \(NSLocalizedString("COMPLETED", comment: ""))",
                                    textColor: appColors.primary,
                                    backgroundColor: appColors.primaryBackground,
                                    action: {
                                        router.navigate(to: .authentication(.user(.userSettings(.History(.fixed)))))
                                    },
                                    iconColor: appColors.primary
                                )
                                
                                Spacer()
                                    .frame(width: 40)
                                
                                PillCountingButton(
                                    iconName: "partial",
                                    title:"\(userViewModel.fixedCountTransactionPartialCount) \(NSLocalizedString("PENDING", comment: ""))",
                                    textColor: appColors.primary,
                                    backgroundColor: appColors.primaryBackground,
                                    action: {
                                        router.selectedPillScanningType = .FIXED
                                        router.navigate(
                                            to: .authentication(
                                                .login(
                                                    .dashboard(.fixedCountPartial)))
                                        )
                                    },
                                    iconColor: appColors.primary
                                )
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 20)
                            
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(appColors.secondaryBackground)
                        .onTapGesture {
                            router.selectedPillScanningType = .FIXED
                            router.navigate(
                                to: .authentication(
                                    .login(
                                        .dashboard(
                                            .pillCount(.barcodeScanning(.rx_label))))))
                        }
                    }
                },
                bottomContent: {
                    GeometryReader { geometry in
                        VStack(spacing: 10) {
                            Spacer()
                            Spacer()
                            Image("placeholder_history")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 75, height: 75)
                                .foregroundColor(appColors.secondary)
                                .padding(32)
                                .background(
                                    ZStack {
                                        Circle()
                                            .stroke(appColors.primary.opacity(0.3), lineWidth: 7)
                                            .blur(radius: 5)
                                        Circle()
                                            .stroke(appColors.primary, lineWidth: 4)
                                    }
                                )
                            
                            
                            Spacer().frame(height: 15)
                            
                            Text("REGULAR_COUNT_TITLE")
                                .font(.title)
                                .foregroundStyle(appColors.secondary)
                            
                            Text("REGULAR_COUNT_SUBTITLE")
                                .foregroundStyle(appColors.text)
                            
                            Spacer()
                            
                            HStack {
                                PillCountingButton(
                                    iconName: "check_with_circle",
                                    title: "\(stockCountViewModel.totalCompletedBatchCount) \(NSLocalizedString("COMPLETED", comment: ""))",
                                    textColor: appColors.primary,
                                    backgroundColor: appColors.secondaryBackground,
                                    action: {
                                        router.navigate(to: .authentication(.user(.userSettings(.History(.regular)))))
                                    },
                                    iconColor: appColors.primary,
                                )
                                
                                Spacer()
                                    .frame(width: 40)
                                
                                PillCountingButton(
                                    iconName: "partial",
                                    title: "\(stockCountViewModel.totalBatchCount) \(NSLocalizedString("PENDING", comment: ""))",
                                    textColor: appColors.primary,
                                    backgroundColor: appColors.secondaryBackground,
                                    action: {
                                        router.navigate(to: .authentication(.login(.dashboard(.pillCount(.stockCount(.stockCountPartialBatchListScreen))))))
                                    },
                                    iconColor: appColors.primary
                                )
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 20)
                            
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(appColors.primaryBackground)
                        .cornerRadius(24)
                        .onTapGesture {
                            router.selectedPillScanningType = .REGULAR
                            showStockCountPopup.toggle()
                            resetStockCountSelection()
                        }
                        
                    }
                },
                showBackButton: false,
                showHamburgerMenu: true,
                showPmsConnectionButton: isHl7Enable,
                pmsConnectionState : userViewModel.pmsConnectionState
            )
            
            if pillScanViewModel.showToast  {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image("app_icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)

                        Text(pillScanViewModel.toastMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(10)
                    .padding(.bottom, 32)  // distance from bottom
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: pillScanViewModel.showToast)
            }
            
        }
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
                Task {
                    await userViewModel.getUser()
                    stockCountViewModel.getCountData()
                }
            }
            
            locationService.requestPermission()
            locationService.startUpdating()
        }
        .customPopup(isPresented: $showStockCountPopup) {
            stockCountPopUp
        }
        .customPopup(isPresented: $showSelectBucketIdPopup ){
            selectBucketPopUp
        }
        

    }
    
    private var stockCountPopUp: some View {
        return (
            VStack(spacing: 35) {
                
                // title for the pop up.
                VStack (alignment: .leading) {
                    Text(NSLocalizedString("WHAT_WOULD_YOU_DO", comment: ""))
                        .font(.system(size: 16))
                        .fontWeight(.semibold)
                        .foregroundStyle(appColors.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    
                // radio options for the buttons.
                VStack(alignment: .leading, spacing: 28) {
                    PillCountingRadioButton(
                            option: StockCountOption.newBatch,
                            selectedOption: $selectedStockCountOption,
                            label: NSLocalizedString("CREATE_NEW_BATCH", comment: ""),
                            selectedColor: appColors.secondary,
                            unselectedColor: .gray,
                            size: 20,
                            lineWidth: 2,
                            textColor: appColors.text
                    )
                    PillCountingRadioButton(
                            option: StockCountOption.existingBatch,
                            selectedOption: $selectedStockCountOption,
                            label: NSLocalizedString("CONTINUE_LAST_BATCH", comment: ""),
                            selectedColor: appColors.secondary,
                            unselectedColor: .gray,
                            size: 20,
                            lineWidth: 2,
                            textColor: appColors.text
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                
                // action buttons for the pop up
                EqualWidthHStackButtons(spacing: 20) {

                    // DELETE
                    PillCountingButton(
                        iconName: nil,
                        title: NSLocalizedString("CANCEL", comment: ""),
                        textColor: appColors.text,
                        backgroundColor: .clear,
                        borderColor: appColors.primary,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 32,
                        verticalPadding: 20,
                        iconSize: 0,
                        action: {
                            showStockCountPopup = false
                        }
                    )

                    // OK
                    PillCountingButton(
                        iconName: nil,
                        title: "OK",
                        textColor: Color.white,
                        backgroundColor: appColors.primary,
                        borderColor: .clear,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 32,
                        verticalPadding: 20,
                        iconSize: 0,
                        action: {
                            //Load Buckets
                            switch selectedStockCountOption {
                            case .newBatch:
                                let buckets = userViewModel.bucket
                                pillScanViewModel.bucketOptions = buckets
                                pillScanViewModel.selectedBucket = buckets.first ?? ""
                                showSelectBucketIdPopup = true
                                showStockCountPopup = false
                            case .existingBatch:
                                if stockCountViewModel.continueLastBatch() {
                                    handleStockCountSelectedOption()
                                }else{
                                    pillScanViewModel.showToastMessage(text: "No last batch found")
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
        )
    }
    
    private var selectBucketPopUp: some View {
        return (
            VStack(spacing: 35) {
                
                // title for the pop up.
                VStack (alignment: .leading) {
                    Text(NSLocalizedString("SELECT_BUCKET", comment: ""))
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
                        title: NSLocalizedString("CANCEL", comment: ""),
                        textColor: appColors.text,
                        backgroundColor: .clear,
                        borderColor: appColors.primary,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 32,
                        verticalPadding: 20,
                        iconSize: 0,
                        action: {
                            showSelectBucketIdPopup = false
                        }
                    )
                    PillCountingButton(
                        iconName: nil,
                        title: "OK",
                        textColor: Color.white,
                        backgroundColor: appColors.primary,
                        borderColor: .clear,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 32,
                        verticalPadding: 20,
                        iconSize: 0,
                        action: {
                            handleStockCountSelectedOption()
                            showSelectBucketIdPopup = false
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
            
            }.padding(.horizontal, 8)
        )
    }
    
    private func handleStockCountSelectedOption() {
        stockCountViewModel.createNewBatch(bucketId: pillScanViewModel.selectedBucket)
        router.selectedPillScanningType = .REGULAR
        router.navigate(to: .authentication(.login(.dashboard(.pillCount(.barcodeScanning(.stockCount))))))
        resetStockCountSelection()
    }
    
    private func resetStockCountSelection() {
        selectedStockCountOption = .newBatch
    }
}

#Preview {
    DashboardView()
}
