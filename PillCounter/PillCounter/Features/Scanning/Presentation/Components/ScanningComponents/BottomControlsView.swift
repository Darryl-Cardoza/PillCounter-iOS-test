//
//  BottomControlsView.swift
//  PillCounter
//

import SwiftUI

// MARK: - Container

struct BottomControlsView: View {

    let isLandscape: Bool
    let pillScanViewModel: PillScanViewModel
    let cameraService: CameraService
    let appColors: AppColors
    var isAddButtonDisabled: Bool = false
    let onAddPill: () -> Void
    let onComplete: () -> Void
    let onReset: () -> Void
    let onShowDetailGrid: () -> Void
    @Binding var showTransactionDetails: Bool
    @Binding var isPaused: Bool

    @EnvironmentObject private var router: Router

    var targetCount: Int32 {
        if pillScanViewModel.currentTransaction?.is_from_pms == true {
            return Int32(pillScanViewModel.currentControlledTargetCount ?? 0)
        } else if pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue {
            return 0
        } else {
            return Int32(pillScanViewModel.currentControlledTargetCount ?? 0)
        }
    }

    var completeCount: Int {
        if pillScanViewModel.currentTransaction?.is_from_pms == true {
            return Int(pillScanViewModel.getTotalCuntForCurrentStep())
        } else if pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue {
            return pillScanViewModel.addCurrentOpenPillCount
        } else {
            return pillScanViewModel.getTotalPillCountOfCurrentTransaction()
        }
    }

    var body: some View {
        let isIpad = UIDevice.current.userInterfaceIdiom == .pad

        VStack(spacing: 0) {
            BottomControlsViewHeader(
                drugName: pillScanViewModel.currentTransaction?.drug?.drug_name ?? "",
                isLandScape: isLandscape,
                isIpad: isIpad
            )
            .padding(.top, isIpad ? 42 : 24)

            if !isIpad { Spacer() }

            VStack {
                BottomControlsViewBodyForPillScan(
                    appColors: appColors,
                    countType: router.selectedPillScanningType ?? .FIXED,
                    targetCount: targetCount,
                    currentTotalCount: completeCount,
                    currentScanningCount: cameraService.stableCount,
                    onAddPills: onAddPill,
                    onCompleteScan: onComplete,
                    onShowDetailGrid: onShowDetailGrid,
                    isLandscape: isLandscape,
                    isPausedDueToInactivity: cameraService.isPausedDueToInactivity,
                    isAddButtonDisabled: isAddButtonDisabled
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Body (pill scan controls)

struct BottomControlsViewBodyForPillScan: View {

    let appColors: AppColors
    let countType: CountType
    let targetCount: Int32?
    let currentTotalCount: Int
    let currentScanningCount: Int
    let onAddPills: () -> Void
    let onCompleteScan: () -> Void
    let onShowDetailGrid: () -> Void
    let isLandscape: Bool
    let isPausedDueToInactivity: Bool
    var isAddButtonDisabled: Bool

    @State private var isAnimating: Bool = true
    @State private var stabilityWorkItem: DispatchWorkItem?
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel

    var body: some View {
        let isIpad = UIDevice.current.userInterfaceIdiom == .pad

        Group {
            if isLandscape {
                VStack(spacing: 0) {
                    addButton
                        .frame(width: isIpad ? 160 : 120, height: isIpad ? 600 : 120)
                        .frame(maxWidth: .infinity)
                        .padding(.top, isIpad ? 12 : 48)
                    Spacer()
                    HStack(alignment: .center, spacing: 16) {
                        totalCountView
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                if pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
                                    onShowDetailGrid()
                                }
                            }
                        Spacer()
                        allDoneButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, isIpad ? 40 : 16)
                    .padding(.bottom, isIpad ? 36 : 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .center) {
                    totalCountView
                        .frame(maxWidth: .infinity, alignment: .center)
                        .onTapGesture {
                            if pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue {
                                onShowDetailGrid()
                            }
                        }
                        .padding(.bottom, isIpad ? 64 : 20)
                    addButton
                        .frame(maxWidth: .infinity, alignment: .center)
                    allDoneButton
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, isIpad ? 64 : 20)
                }
                .padding(.horizontal)
                .padding(.vertical, 20)
            }
        }
        .cornerRadius(24)
        .onAppear {
            if !isPausedDueToInactivity { handleCountChange() }
        }
        .onChange(of: isPausedDueToInactivity) { _, paused in
            if paused {
                stabilityWorkItem?.cancel()
                withAnimation { isAnimating = false }
            } else {
                handleCountChange()
            }
        }
        .onChange(of: currentScanningCount) { _, _ in handleCountChange() }
    }

    @ViewBuilder
    private var addButton: some View {
        CountAddButtonView(
            count: currentScanningCount,
            ringColor: appColors.secondary,
            buttonColor: appColors.primary,
            textColor: appColors.text,
            ringLineWidth: 3,
            size: 120,
            isAnimating: isAnimating,
            onAddTap: { onAddPills() },
            isDisabled: isAddButtonDisabled,
            isLandscape: isLandscape,
            appColors: appColors
        )
    }

    @ViewBuilder
    private var totalCountView: some View {
        TotalCountView(
            currentTotalCount: currentTotalCount,
            targetCount: targetCount,
            countType: countType,
            appColors: appColors,
            isLandscape: isLandscape
        )
    }

    @ViewBuilder
    private var allDoneButton: some View {
        Button { onCompleteScan() } label: {
            VStack(spacing: 6) {
                Spacer()
                Image("all_done")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .overlay(appColors.primary)
                    .mask(Image("all_done").resizable().scaledToFit())
                if isLandscape {
                    Spacer().frame(height: 8)
                } else {
                    Spacer().frame(height: 12)
                }
                Text(L10n.PillCount.allDone)
                    .foregroundStyle(appColors.text)
                    .font(.system(size: 16))
            }
        }
    }

    private func handleCountChange() {
        guard !isPausedDueToInactivity else { return }
        if !isAnimating { isAnimating = true }
        stabilityWorkItem?.cancel()
        let workItem = DispatchWorkItem { withAnimation { isAnimating = false } }
        stabilityWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}

// MARK: - Header

struct BottomControlsViewHeader: View {
    let drugName: String
    let isLandScape: Bool
    let isIpad: Bool
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        Group {
            if isLandScape {
                VStack(spacing: 2) {
                    Text(drugName)
                        .foregroundStyle(appColors.text)
                        .font(.system(size: isIpad ? 20 :16))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                }
            } else {
                ZStack {
                    Text(drugName)
                        .foregroundStyle(appColors.text)
                        .font(.system(size: isIpad ? 20 : 16))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
}


// MARK: - Total count display

struct TotalCountView: View {

    let currentTotalCount: Int
    let targetCount: Int32?
    let countType: CountType
    let appColors: AppColors
    let isLandscape: Bool

    private var showTarget: Bool {
        countType == .FIXED && (targetCount ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("\(currentTotalCount)")
                .foregroundStyle(appColors.primary)
                .font(.system(size: showTarget ? 26 : 30, weight: .bold))
            if showTarget {
                Rectangle()
                    .fill(appColors.primary)
                    .frame(width: 65, height: 1.5)
                Text("\(targetCount ?? 0)")
                    .foregroundStyle(appColors.primary)
                    .font(.system(size: 26, weight: .bold))
            }
            if !showTarget { Spacer().frame(height: 10) }
            Text(L10n.PillCount.totalCount)
                .foregroundStyle(appColors.text)
                .font(.system(size: 16))
                .padding(.top, 8)
        }
    }
}
