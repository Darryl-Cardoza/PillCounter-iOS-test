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
    
    @StateObject private var dashboardViewModel =  DashboardViewModel()


    var userId: String { AppStorageManager.shared.userId ?? "" }
    var isNewUser: Bool { AppStorageManager.shared.isNewUser }
    var isHl7Enable: Bool { AppStorageManager.shared.isHl7Enabled }

    @State private var showStockCountPopup: Bool = false
    @State private var selectedStockCountOption: StockCountOption = .newBatch
    @State private var showSelectBucketIdPopup : Bool = false
    
    
    // MARK: - LOCAL STATE
    // This ensures we only redirect once per session (prevents infinite loop on Skip)
    @State private var hasCheckedNewUser: Bool = false
    
    // For animation
//    @State private var isDispenseIconAnimating = false
//    @State private var isStockIconAnimating = false
//    
    //PMS
    @State private var pmsToastMessage: String = ""
    @State private var pmsToastColor: Color = .green
    @State private var showPmsToast: Bool = false
    @State private var pmsToastTask: Task<Void, Never>? = nil

    private var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var scale: CGFloat {
        isIpad ? 1.5 : 1.0
    }

    var body: some View {
        ZStack {
            BaseView(
                topRatio: 0.5,
                topContent: {
                    VStack(spacing: 10) {
                        Spacer()
                        Spacer()
                        VStack(spacing: 15) {
                            Image("dispense_dashboard_icon")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: isIpad ? 80 : 60,
                                    height: isIpad ? 80 : 60
                                )
                                .foregroundColor(appColors.secondary)
                                .padding(40 * scale)
                                .background(
                                    ZStack {
                                        Circle()
                                            .stroke(appColors.primary.opacity(0.3), lineWidth: 9)
                                            .blur(radius: 5 * scale)
                                        Circle()
                                            .stroke(appColors.primary, lineWidth: 4 )
                                    }
                                )
                            
                            Spacer()
                                .frame(height: isIpad ? 15 : 0)
                            
                            VStack(spacing: 8){
                                Text(L10n.Dashboard.FixedCount.title)
                                    .font(.title)
                                    .foregroundStyle(appColors.secondary)

                                Text(L10n.Dashboard.FixedCount.subtitle)
                                    .foregroundStyle(appColors.text)
                            }
                            
                        }
                        .padding(isIpad ? 30 : 0)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            router.selectedPillScanningType = .FIXED
                            router.navigate(
                                to: .authentication(
                                    .login(
                                        .dashboard(
                                            .pillCount(.scan(.rx_label))))))
                        }

                        if isIpad{
                            Spacer()
                        }
                        HStack(spacing: isIpad ? 24 : 0) {
                            PillCountingButton(
                                iconName: "check_with_circle",
                                title: "\(userViewModel.fixedCountTransactionCompletedCount) \(L10n.Dashboard.completed)",
                                textColor: appColors.primary,
                                backgroundColor: appColors.primaryBackground.opacity(0.4),
                                action: {
                                    router.navigate(to: .authentication(.user(.userSettings(.History(.fixed, .completed)))))
                                },
                                iconColor: appColors.primary
                            )
                            .frame(maxWidth: .infinity)

                            Spacer()
                                .frame(width: isIpad ? 70 : 20)
                         
                            PillCountingButton(
                                iconName: "partial",
                                title: "\(userViewModel.fixedCountTransactionPartialCount) \(L10n.Dashboard.pending)",
                                textColor: appColors.primary,
                                backgroundColor: appColors.primaryBackground.opacity(0.4),
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
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appColors.secondaryBackground)

                },
                bottomContent: {
                    VStack(spacing: 10) {
                        Spacer()
                        Spacer()
                        VStack(spacing: 15) {
                            Image("placeholder_history")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: isIpad ? 90 : 65,
                                    height: isIpad ? 90 : 65
                                )
                                .foregroundColor(appColors.secondary)
                                .padding(40 * scale)
                                .background(
                                    ZStack {
                                        Circle()
                                            .stroke(appColors.primary.opacity(0.3), lineWidth: 9 )
                                            .blur(radius: 5 * scale)
                                        Circle()
                                            .stroke(appColors.primary, lineWidth: 4)
                                    }
                                )
                    
                            Spacer()
                                .frame(height: isIpad ? 15 : 0)
                            
                            VStack(spacing: 8){
                                Text(L10n.Dashboard.RegularCount.title)
                                    .font(.title)
                                    .foregroundStyle(appColors.secondary)

                                Text(L10n.Dashboard.RegularCount.subtitle)
                                    .foregroundStyle(appColors.text)
                            }
                            
                        }
                        .padding(isIpad ? 30 : 0)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            router.selectedPillScanningType = .REGULAR
                            showStockCountPopup.toggle()
                            resetStockCountSelection()
                        }
                        if isIpad{
                            Spacer()
                        }
                        HStack(spacing: isIpad ? 24 : 0) {
                            PillCountingButton(
                                iconName: "check_with_circle",
                                title: "\(stockCountViewModel.totalCompletedBatchCount) \(L10n.Dashboard.completed)",
                                textColor: appColors.primary,
                                backgroundColor: appColors.secondaryBackground.opacity(0.4),
                                action: {
                                    router.navigate(to: .authentication(.user(.userSettings(.History(.regular, .completed)))))
                                },
                                iconColor: appColors.primary
                            )
                            .frame(maxWidth: .infinity)

                            Spacer()
                                .frame(width: isIpad ? 70 : 10)
                         
                            PillCountingButton(
                                iconName: "partial",
                                title: "\(stockCountViewModel.totalBatchCount) \(L10n.Dashboard.pending)",
                                textColor: appColors.primary,
                                backgroundColor: appColors.secondaryBackground.opacity(0.4),
                                action: {
                                    router.navigate(to: .authentication(.login(.dashboard(.pillCount(.stockCount(.stockCountPartialBatchListScreen))))))
                                },
                                iconColor: appColors.primary
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appColors.primaryBackground)
                    .cornerRadius(24)
                },
                showBackButton: false,
                showHamburgerMenu: true,
                showPmsConnectionButton: isHl7Enable,
                pmsConnectionState : userViewModel.pmsConnectionState,
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
            //Animation 
//            isStockIconAnimating = true
//            isDispenseIconAnimating = true
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
//                isStockIconAnimating = false
//                isDispenseIconAnimating = false
//            }
//            
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
                    Text(L10n.Dashboard.Popup.whatWouldYouDo)
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
                
                
                // action buttons for the pop up
                EqualWidthHStackButtons(spacing: 20) {

                    // DELETE
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
                        action: {
                            showStockCountPopup = false
                        }
                    )

                    // OK
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
                            //Load Buckets
                            switch selectedStockCountOption {
                            case .newBatch:
                                print("New batch")
                                let buckets = userViewModel.bucket
                                pillScanViewModel.bucketOptions = buckets
                                pillScanViewModel.selectedBucket = buckets.first ?? ""
                                showSelectBucketIdPopup = true
                                showStockCountPopup = false
                            case .existingBatch:
                                print("Existing batch")
                                if stockCountViewModel.continueLastBatch() {
                                    print("Fetch data")
                                    router.selectedPillScanningType = .REGULAR
                                    router.navigate(to: .authentication(.login(.dashboard(.pillCount(.scan(.stockCount))))))
                                    resetStockCountSelection()
                                }else{
                                    print("show toast")
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
        )
    }
    
    private var selectBucketPopUp: some View {
        return (
            VStack(spacing: 35) {
                
                // title for the pop up.
                VStack (alignment: .leading) {
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
                        action: {
                            showSelectBucketIdPopup = false
                        }
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
                            handleStockCountSelectedOption()
                            showSelectBucketIdPopup = false
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
            
            }.padding(.horizontal, 8)
        )
    }
    
    private func showPmsStatusToast(message: String, color: Color) {
        pmsToastMessage = message
        pmsToastColor = color
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            showPmsToast = true
        }
        pmsToastTask?.cancel()
        pmsToastTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showPmsToast = false
                }
            }
        }
    }
    
    private func handleStockCountSelectedOption() {
        stockCountViewModel.createNewBatch(bucketId: pillScanViewModel.selectedBucket)
        router.selectedPillScanningType = .REGULAR
        router.navigate(to: .authentication(.login(.dashboard(.pillCount(.scan(.stockCount))))))
        resetStockCountSelection()
    }
    
  
    
    private func resetStockCountSelection() {
        selectedStockCountOption = .newBatch
    }
}


