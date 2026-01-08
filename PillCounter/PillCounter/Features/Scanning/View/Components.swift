//
//  Components.swift
//  PillCounter
//
//  Created by HC on 29/12/25.
//

import SwiftUI

// MARK: - CAMERA CONTENT VIEW
// Wraps the UIKit camera view and the ML detection overlay.
struct CameraContentView: View {
    @ObservedObject var cameraService: CameraService
    @EnvironmentObject var appColors: AppColors

    var body: some View {
        ZStack {
            // CAMERA + OVERLAY
            ZStack(alignment: .bottomTrailing) {
                if cameraService.isAuthorized {
                    CameraView(
                        session: cameraService.getSession(),
                        cameraService: cameraService
                    )
                    .ignoresSafeArea()
                    .task { cameraService.start() }
                    .onDisappear { cameraService.stop() }

                    DetectionOverlay(cameraService: cameraService)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
            }

        }
    }
}

// MARK: - BOTTOM CONTROLS VIEW
// The container for the pill info, count display, and buttons.
struct BottomControlsView: View {
    let isLandscape: Bool
    let pillScanViewModel: PillScanViewModel
    let cameraService: CameraService
    let appColors: AppColors
    let onAddPill: () -> Void
    let onComplete: () -> Void
    let onReset: () -> Void
    let onTransactionDetailTapped: (PillCountTransactionDetailsEntity) -> Void
    @Binding var showTransactionDetails: Bool
    @Binding var isPaused: Bool

    @State private var showHistoryOrScanPillIcon: Bool = false

    @EnvironmentObject private var router: Router

    var body: some View {
        VStack(spacing: 0) {

            // MARK: HEADER
            BottomControlsViewHeader(
                drugName: pillScanViewModel.currentTransaction?.drug?.drug_name
                    ?? "",
                isLandScape: isLandscape,
                isScanPill: $showHistoryOrScanPillIcon,
                onResetPills: onReset
            )
            .padding()

            // MARK: BODY
            VStack {
                if showHistoryOrScanPillIcon {
                    BottonControlsViewForTransactionList(
                        details: pillScanViewModel
                            .currentTransactionTransactionDetails ?? [],
                        appColors: appColors,
                        countType: router.selectedPillScanningType ?? .FIXED,
                        targetCount: pillScanViewModel.currentTransaction?
                            .target_count ?? 0,
                        onTap: onTransactionDetailTapped,
                        isLandscape: isLandscape
                    )
                    .padding(.trailing, isLandscape ? 20 : 0)
                } else {
                    BottomControlsViewBodyForPillScan(
                        appColors: appColors,
                        countType: router.selectedPillScanningType ?? .FIXED,
                        targetCount: pillScanViewModel.currentTransaction?
                            .target_count ?? 0,
                        currentTotalCount:
                            pillScanViewModel
                            .getTotalPillCountOfCurrentTransaction(),
                        currentScanningCount: cameraService.stableCount,
                        onAddPills: onAddPill,
                        onCompleteScan: onComplete,
                        isLandscape: isLandscape,
                        isPausedDueToInactivity: cameraService.isPausedDueToInactivity
                    )
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

    }
}

struct CountAddButtonView: View {
    let count: Int
    let ringColor: Color
    let buttonColor: Color
    let textColor: Color
    let ringLineWidth: CGFloat
    let size: CGFloat
    let isAnimating: Bool
    let onAddTap: () -> Void

    @State private var animateStroke: Bool = false

    var body: some View {
        VStack(spacing: -20) {

            // Circle with animated stroke
            ZStack {
                Circle()
                    .trim(from: 0, to: animateStroke ? 1 : 0)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(
                            lineWidth: ringLineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(90))  // start at 6 o'clock
                    .frame(width: size, height: size)
                    .onAppear {
                        startOrStopAnimation()
                    }
                    .onChange(of: isAnimating) { _, _ in
                        startOrStopAnimation()
                    }

                Text("\(count)")
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(textColor)
            }

            // Add button
            Button(action: onAddTap) {
                Text("Add")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(buttonColor)
                    .clipShape(Capsule())
            }
        }
    }

    private func startOrStopAnimation() {
        if isAnimating {
            animateStroke = false
            withAnimation(
                .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                animateStroke = true
            }
        } else {
            animateStroke = false
        }
    }
}

struct BottomControlsViewBodyForPillScan: View {

    let appColors: AppColors
    let countType: CountType
    let targetCount: Int32?
    let currentTotalCount: Int
    let currentScanningCount: Int
    let onAddPills: () -> Void
    let onCompleteScan: () -> Void
    let isLandscape: Bool
    let isPausedDueToInactivity: Bool
    
    @State private var isAnimating: Bool = true
    @State private var lastCount: Int = -1
    @State private var lastChangeTime: Date = Date()
    
    private let minStableSeconds: TimeInterval = 2
    private let maxStableSeconds: TimeInterval = 5

    var body: some View {
        VStack {
            HStack {
                if !isLandscape {
                    TotalCountView(
                        currentTotalCount: currentTotalCount,
                        targetCount: targetCount,
                        countType: countType,
                        appColors: appColors
                    )

                    Spacer()
                }

                CountAddButtonView(
                    count: currentScanningCount,
                    ringColor: appColors.secondary,
                    buttonColor: appColors.primary,
                    textColor: appColors.text,
                    ringLineWidth: 5,
                    size: 120,
                    isAnimating: isAnimating
                ) {
                    onAddPills()
                }

                if !isLandscape {
                    Spacer()

                    Button {
                        // some action
                        onCompleteScan()
                    } label: {
                        VStack(spacing: 6) {
                            Image("all_done")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .overlay(appColors.primary)
                                .mask(
                                    Image("all_done")
                                        .resizable()
                                        .scaledToFit()
                                )

                            Text("All Done")
                                .foregroundStyle(appColors.text)
                                .font(.system(size: 16))
                        }
                    }
                }
            }

            if isLandscape {
                HStack {
                    TotalCountView(
                        currentTotalCount: currentTotalCount,
                        targetCount: targetCount,
                        countType: countType,
                        appColors: appColors
                    )

                    Spacer()

                    Button {
                        // some action
                        onCompleteScan()
                    } label: {
                        VStack(spacing: 6) {
                            Image("all_done")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .overlay(appColors.primary)
                                .mask(
                                    Image("all_done")
                                        .resizable()
                                        .scaledToFit()
                                )

                            Text("All Done")
                                .foregroundStyle(appColors.text)
                                .font(.system(size: 16))
                        }
                    }
                }
            }
        }
        .onChange(of: isPausedDueToInactivity) { _, paused in
            if paused {
                isAnimating = false
            } else {
                // Camera resumed → restart animation
                lastChangeTime = Date()
                isAnimating = true
            }
        }
        .onChange(of: currentScanningCount) { _, newValue in
            let now = Date()
            
            guard !isPausedDueToInactivity else {
                isAnimating = false
                return
            }
            
            if newValue != lastCount {
                lastCount = newValue
                lastChangeTime = now
                isAnimating = true
            } else {
                let elapsed = now.timeIntervalSince(lastChangeTime)
                
                if elapsed >= minStableSeconds && elapsed <= maxStableSeconds {
                    isAnimating = false
                }
            }
        }
        
    }
}

struct TotalCountView: View {
    let currentTotalCount: Int
    let targetCount: Int32?
    let countType: CountType
    let appColors: AppColors

    var body: some View {
        VStack(spacing: 6) {

            // Current Total
            Text("\(currentTotalCount)")
                .foregroundStyle(appColors.primary)
                .font(.system(size: 26, weight: .bold))

            // Divider (ONLY for FIXED + target exists)
            if countType == .FIXED, targetCount != nil {
                Rectangle()
                    .fill(appColors.primary)
                    .frame(width: 65, height: 1.5)
            }

            // Target Count (ONLY for FIXED)
            if countType == .FIXED, let targetCount {
                Text("\(targetCount)")
                    .foregroundStyle(appColors.primary)
                    .font(.system(size: 20, weight: .bold))
            }

            // Label
            Text("Total Count")
                .foregroundStyle(appColors.text)
                .padding(.top, 8)
        }
    }
}

struct BottonControlsViewForTransactionList: View {

    let details: [PillCountTransactionDetailsEntity]
    let appColors: AppColors
    let countType: CountType
    let targetCount: Int32?
    let onTap: (PillCountTransactionDetailsEntity) -> Void
    let isLandscape: Bool

    private var totalCount: Int {
        details.reduce(0) { $0 + Int($1.pill_count) }
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {

                        Spacer(minLength: 0)

                        ForEach(details.indices, id: \.self) { index in
                            let item = details[index]
                            let isLast = index == details.count - 1

                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isLast
                                        ? appColors.secondary
                                        : appColors.primary,
                                    lineWidth: 2
                                )
                                .frame(width: 50, height: 80)
                                .overlay(
                                    Text("\(item.pill_count)")
                                        .foregroundColor(appColors.text)
                                        .font(
                                            isLast
                                                ? .headline.bold() : .headline)
                                )
                                .id(index)
                                .onTapGesture { onTap(item) }
                        }

                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 80)
                .onAppear { scrollToLast(proxy) }
                .onChange(of: details.count) { _, _ in
                    scrollToLast(proxy)
                }
            }
            
            if !isLandscape {
                Text("Total Count")
                    .font(.caption)
                    .foregroundColor(appColors.text)
                    .padding(.top, 15)

                HStack(spacing: 4) {
                    Text("\(totalCount)")
                        .font(.title.bold())
                        .foregroundColor(appColors.primary)

                    if countType == .FIXED, let targetCount {
                        Text("/ \(targetCount)")
                            .font(.body)
                            .foregroundColor(appColors.primary)
                    }
                }
            } else {
                TotalCountView(
                    currentTotalCount: totalCount,
                    targetCount: targetCount,
                    countType: countType,
                    appColors: appColors
                )
                .padding(.top, 20)
            }
        }
        .padding(.top, 8)
    }
    private func scrollToLast(_ proxy: ScrollViewProxy) {
        guard !details.isEmpty else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(details.count - 1, anchor: .center)
            }
        }
    }
}

struct BottomControlsViewHeader: View {
    let drugName: String
    let isLandScape: Bool
    @EnvironmentObject private var appColors: AppColors
    @Binding var isScanPill: Bool
    let onResetPills: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    // some action to be taken
                    onResetPills()
                } label: {
                    Image("reset_pills")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .overlay(
                            appColors.primary
                        )
                        .mask(
                            Image("reset_pills")
                                .resizable()
                                .scaledToFit()
                        )
                }

                if !isLandScape {
                    Spacer()

                    Text(drugName)
                        .foregroundStyle(appColors.text)
                        .font(.system(size: 20))
                }

                Spacer()

                if isScanPill {
                    Button {
                        // some action to be taken
                        isScanPill = false
                    } label: {
                        Image("scan_pill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .overlay(
                                appColors.primary
                            )
                            .mask(
                                Image("scan_pill")
                                    .resizable()
                                    .scaledToFit()
                            )
                    }
                } else {
                    Button {
                        // some action to be taken
                        isScanPill = true
                    } label: {
                        Image("history_icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .overlay(
                                appColors.primary
                            )
                            .mask(
                                Image("history_icon")
                                    .resizable()
                                    .scaledToFit()
                            )
                    }
                }
            }

            if isLandScape {
                Text(drugName)
                    .foregroundStyle(appColors.text)
                    .font(.system(size: 20))
            }
        }
    }
}

// MARK: - CIRCLE BADGE COMPONENT
// A reusable animated circle for displaying counts.
struct CircleBadge: View {
    let size: CGFloat
    let strokeWidth: CGFloat
    let outerColor: Color
    let innerColor: Color
    let text: String
    let textColor: Color
    let font: Font
    let isAnimated: Bool

    @State private var trimValue: CGFloat = 1
    @State private var animationID = UUID()  // ⬅️ animation reset key

    var body: some View {
        ZStack {

            Circle()
                .trim(from: 0, to: trimValue)
                .stroke(
                    outerColor,
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .id(animationID)  // ⬅️ forces SwiftUI to kill animation
                .onAppear {
                    handleAnimationChange()
                }
                .onChange(of: isAnimated) { _, _ in
                    handleAnimationChange()
                }

            Circle()
                .fill(innerColor)
                .frame(
                    width: size - strokeWidth * 3,
                    height: size - strokeWidth * 3
                )

            Text(text)
                .font(font)
                .foregroundColor(textColor)
                .contentTransition(.numericText())
        }
        .onChange(of: text) { oldValue, newValue in
            if oldValue != newValue {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    // MARK: - ANIMATION CONTROL
    private func handleAnimationChange() {
        animationID = UUID()  // kills any running repeatForever

        if isAnimated {
            trimValue = 0
            withAnimation(
                .linear(duration: 1.2).repeatForever(autoreverses: false)
            ) {
                trimValue = 1
            }
        } else {
            // Pause → static full circle
            trimValue = 1
        }
    }
}
