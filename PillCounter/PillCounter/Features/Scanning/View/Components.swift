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
    @EnvironmentObject var pillScanViewModel: PillScanViewModel
    @State private var isAutoOrManual: Bool = false
    @Environment(\.isLandscape) private var isLandscape
    
    var isCameraEnabled: Bool
    
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
                    .task {
                        cameraService.configureInitialOrientation()
                        cameraService.startObservingOrientation()
                        
                        if isCameraEnabled {
                            cameraService.start()
                        }
                    }
                    .onChange(of: isCameraEnabled) { _, enabled in
                        if enabled {
                            cameraService.start()
                        } else {
                            cameraService.stop()
                        }
                    }
                    .onDisappear { cameraService.stop() }
                    .padding(.top, isLandscape ? 0 : 30)

                    if pillScanViewModel.currentControlledStep != .vial{
                        DetectionOverlay(cameraService: cameraService)
                            .ignoresSafeArea()
                        TrayOverlay(cameraService: cameraService)
                            .ignoresSafeArea()
                    }
                    if pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue
                    {
                        VStack {
                            ControlledStepRow(
                                activeSteps: PillCountingStepResolver.getActiveSteps(txn: pillScanViewModel.currentTransaction),
                                currentStep: pillScanViewModel.currentControlledStep
                            )
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
            }

        }
    }
    private var headerToggle: some View {
        PillCountingToggleButton(
            isOn: $isAutoOrManual,
            onColor: appColors.secondary,
            offColor: appColors.text.opacity(0.4)
        )
    }
}

struct ZoomControlView: View {

    @ObservedObject var cameraService: CameraService
    @EnvironmentObject var appColors: AppColors

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 2.0

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 8) {
           
                Spacer()

                GeometryReader { geo in
                    let width = geo.size.width

                    let horizontalPadding: CGFloat = 16
                    let usableWidth = width - (horizontalPadding * 2)

                    let percentage = (cameraService.zoomFactor - minZoom) / (maxZoom - minZoom)
                    let thumbX = horizontalPadding + (usableWidth * percentage)

                    ZStack(alignment: .leading) {

                        Slider(
                            value: Binding(
                                get: { cameraService.zoomFactor },
                                set: { newValue in
                                    cameraService.setZoom(newValue)
                                    cameraService.resetInactivityTimer()
                                }
                            ),
                            in: minZoom...maxZoom,
                            step: 0.1
                        )
                        .tint(appColors.secondary)

                        Text(String(format: "%.1fx", cameraService.zoomFactor))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(appColors.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .position(x: thumbX, y: -5)  

                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard usableWidth > 0 else { return }

                                        let percentage = min(
                                            max((value.location.x - horizontalPadding) / usableWidth, 0),
                                            1
                                        )

                                        let zoom = minZoom + (maxZoom - minZoom) * percentage

                                        cameraService.setZoom(zoom)
                                        cameraService.resetInactivityTimer()
                                    }
                            )
                    }
                }
                .frame(height: 60)
                .frame(height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 5)
            .cornerRadius(14)
        }
        .allowsHitTesting(!cameraService.isPausedDueToInactivity)
    }
}

struct ZoomControlViewVertical: View {

    @ObservedObject var cameraService: CameraService
    @EnvironmentObject var appColors: AppColors

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 2.0

    private let trackWidth: CGFloat = 2
    private let thumbSize: CGFloat = 22
    private let verticalPadding: CGFloat = 50

    var body: some View {

        GeometryReader { geo in
            let height       = geo.size.height
            let usableHeight = height - (verticalPadding * 2)
            let percentage   = (cameraService.zoomFactor - minZoom) / (maxZoom - minZoom)

            // top = maxZoom, bottom = minZoom
            let thumbY = height - verticalPadding - (usableHeight * percentage)

            ZStack {

                // Track
                Rectangle()
                    .fill(appColors.secondary)
                    .frame(width: trackWidth, height: usableHeight)
                    .position(x: geo.size.width / 2, y: height / 2)

                // Zoom text (placed before circle)
                Text(String(format: "%.1fx", cameraService.zoomFactor))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .position(x: geo.size.width / 2 - 28, y: thumbY)

                // Circle (UNCHANGED POSITION)
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: geo.size.width / 2, y: thumbY)

                // Drag overlay
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard usableHeight > 0 else { return }

                                let pct = min(
                                    max(
                                        (height - verticalPadding - value.location.y) / usableHeight,
                                        0
                                    ),
                                    1
                                )

                                let zoom = minZoom + (maxZoom - minZoom) * pct
                                cameraService.setZoom(zoom)
                                cameraService.resetInactivityTimer()
                            }
                    )
            }
        }
        .frame(width: 44, height: 340)
        .allowsHitTesting(!cameraService.isPausedDueToInactivity)
    }
}

// Top Step instrcution box
struct PillCountInstructionOverlay: View {
    let text: String
    var backgroundOpacity: Double = 0.5
    var cornerRadius: CGFloat = 24

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundColor(AppColors.shared.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                AppColors.shared.primaryBackground.opacity(backgroundOpacity)
            )
            .cornerRadius(cornerRadius)
    
    }
}

// MARK: - BOTTOM CONTROLS VIEW
// The container for the pill info, count display, and buttons.
struct BottomControlsView: View {
    
    let isLandscape: Bool
    let pillScanViewModel: PillScanViewModel
    let cameraService: CameraService
    let appColors: AppColors
    var isAddButtonDisabled: Bool = false
    let onAddPill: () -> Void
    let onComplete: () -> Void
    let onReset: () -> Void
    let onTransactionDetailTapped: (PillCountTransactionDetailsEntity) -> Void
    @Binding var showTransactionDetails: Bool
    @Binding var isPaused: Bool
    @State private var showHistoryOrScanPillIcon: Bool = false

    @EnvironmentObject private var router: Router
    
    var targetCount: Int32 {
        if pillScanViewModel.currentTransaction?.is_from_pms == true {
            return Int32(pillScanViewModel.currentControlledTargetCount ?? 0)
        }else if(pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue){
            return 0
        } else {
            return Int32(pillScanViewModel.currentControlledTargetCount ?? 0)
        }
    }

    var completeCount: Int {
        if pillScanViewModel.currentTransaction?.is_from_pms == true {
            return Int( pillScanViewModel.getTotalCuntForCurrentStep())
        }else if(pillScanViewModel.currentTransaction?.count_type == CountType.REGULAR.rawValue){
            return pillScanViewModel.addCurrentOpenPillCount
        }else {
            return pillScanViewModel.getTotalPillCountOfCurrentTransaction()
        }
    }
    
    var body: some View {
        let isIpad = UIDevice.current.userInterfaceIdiom == .pad

        VStack(spacing: 0) {
            BottomControlsViewHeader(
                drugName: pillScanViewModel.currentTransaction?.drug?.drug_name
                    ?? "",
                isLandScape: isLandscape,
                isScanPill: $showHistoryOrScanPillIcon,
                onResetPills: onReset
            )
            .padding(.top, isIpad ? 42 : 24)
            
            if !isIpad{
                Spacer()
            }
          
            VStack {
                if showHistoryOrScanPillIcon {
                    BottonControlsViewForTransactionList(
                        details: pillScanViewModel
                            .currentTransactionTransactionDetails ?? [],
                        appColors: appColors,
                        countType: router.selectedPillScanningType ?? .FIXED,
                        targetCount: targetCount ,
                        onTap: onTransactionDetailTapped,
                        isLandscape: isLandscape
                    )
                    .padding(.trailing, isLandscape ? 20 : 0)
                } else {
                    BottomControlsViewBodyForPillScan(
                        appColors: appColors,
                        countType: router.selectedPillScanningType ?? .FIXED,
                        targetCount: targetCount,
                        currentTotalCount: completeCount,
                        currentScanningCount: cameraService.stableCount,
                        onAddPills: onAddPill,
                        onCompleteScan: onComplete,
                        isLandscape: isLandscape,
                        isPausedDueToInactivity: cameraService
                            .isPausedDueToInactivity,
                        isAddButtonDisabled: isAddButtonDisabled
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

    }
}

// MARK: ADD BUTTON-
struct CountAddButtonView: View {
    let count: Int
    let ringColor: Color
    let buttonColor: Color
    let textColor: Color
    let ringLineWidth: CGFloat
    let size: CGFloat
    let isAnimating: Bool
    let onAddTap: () -> Void
    var isDisabled: Bool = false

    @State private var animationID = UUID()
    @State private var trimValue: CGFloat = 1.0
    @State private var displayedCount: Int = 0
    @State private var popScale: CGFloat = 1.0
    @State private var countTimer: Timer? = nil
    
    private var uiScale: CGFloat {
         UIDevice.current.userInterfaceIdiom == .pad ? 1.5 : 1.0
     }

    var body: some View {
        VStack(spacing: -20) {
            ZStack {
                Circle()
                    .trim(from: 0, to: trimValue)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(
                        width: size * uiScale,
                        height: size * uiScale
                    )
                    .id(animationID)
                    .onAppear { updateAnimationState() }
                    .onChange(of: isAnimating) { _, _ in updateAnimationState() }

                Text("\(displayedCount)")
                    .font(.system(
                        size: size * 0.28 * uiScale,
                        weight: .semibold
                    ))
                    .foregroundStyle(textColor)
                    .scaleEffect(popScale)
            }
            .opacity(isDisabled ? 0.5 : 1.0)
            .onChange(of: count) { _, newCount in
                if newCount == 0 {
                    snapToZero()
                } else {
                    animateCount(to: newCount)
                }
            }
            .onAppear {
                displayedCount = count
            }

            Button(action: onAddTap) {
                Text(isDisabled ? "Wait..." : "Add")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(isDisabled ? Color.gray : buttonColor)
                    .clipShape(Capsule())
            }
            .disabled(isDisabled)
        }
        .padding(.top, 10)
    }

    // MARK: - Snap to zero instantly
    private func snapToZero() {
        countTimer?.invalidate()
        countTimer = nil
        displayedCount = 0
        popScale = 1.0
    }

    // MARK: - Fast timer-based count
    private func animateCount(to target: Int) {
        countTimer?.invalidate()
        countTimer = nil

        let start = displayedCount
        let delta = target - start
        guard delta != 0 else { return }

        let stepCount = abs(delta)
        let increment = delta > 0 ? 1 : -1

        // Total roll duration — 40ms per step, max 300ms total
        // e.g. +1 = 40ms (nearly instant), +10 = 300ms (fast ticker)
        let totalDuration: Double = min(Double(stepCount) * 0.04, 0.3)
        let interval: Double = totalDuration / Double(stepCount)

        var current = start

        countTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            current += increment
            displayedCount = current

            // Tiny pop on each tick
            popScale = 1.15
            withAnimation(.spring(response: 0.12, dampingFraction: 0.45)) {
                popScale = 1.0
            }

            if current == target {
                t.invalidate()
                countTimer = nil
            }
        }
        // Fire immediately on main run loop including scroll
        RunLoop.main.add(countTimer!, forMode: .common)
    }

    // MARK: - Ring animation
    private func updateAnimationState() {
        animationID = UUID()
        if isAnimating {
            trimValue = 0
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                trimValue = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                guard isAnimating else { return }
                FeedbackManager.shared.triggerDetectionFeedback(
                    isHapticEnabled: AppStorageManager.shared.isHapticEnabled,
                    isSoundEnabled: AppStorageManager.shared.isSoundEnabled
                )
            }
        } else {
            withAnimation(.linear(duration: 0.2)) {
                trimValue = 1
            }
        }
    }
}

// MARK: PILL SCAN BODY
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
                    // addButton centered — constrain its size so it doesn't grow huge
                    addButton
                        .frame(width: isIpad ? 160 : 120, height: isIpad ? 600 : 120)
                        .frame(maxWidth: .infinity)
                        .padding(.top, isIpad ? 12 : 48)
                    
                    Spacer()
                    
                    // Bottom row: Total Count + All Done
                    HStack(alignment: .center, spacing: 16) {
                        totalCountView
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                if pillScanViewModel.currentTransaction?.count_type ==  CountType.FIXED.rawValue {
                                    pillScanViewModel.isNavigatingToDetailGrid = true
                                    router.navigate(to: .authentication(.login(.dashboard(.pillCount(.pillCountHistoryView)))))
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
                // MARK: - PORTRAIT LAYOUT
                // All three in one bottom-aligned row
                HStack(alignment: .bottom) {
                    totalCountView
                        .frame(maxWidth: .infinity, alignment:  isIpad ? .center : .leading)
                        .padding(.bottom, 12)
                        .onTapGesture {
                            if pillScanViewModel.currentTransaction?.count_type ==  CountType.FIXED.rawValue {
                                pillScanViewModel.isNavigatingToDetailGrid = true
                                router.navigate(to: .authentication(.login(.dashboard(.pillCount(.pillCountHistoryView)))))
                            }
                        }


                    addButton
                        .frame(maxWidth: .infinity)

                    allDoneButton
                        .frame(maxWidth: .infinity, alignment: isIpad  ? .center : .trailing)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal)
                .padding(.bottom,  40)
                .padding(.top, 20)
            }
        }
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
        .onChange(of: currentScanningCount) { _, _ in
            handleCountChange()
        }
    }

    // MARK: - COMPONENT BUILDERS
    // Extracted to avoid code duplication across the if/else layout

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
            isDisabled: isAddButtonDisabled
        )
    }

    @ViewBuilder
    private var totalCountView: some View {
        TotalCountView(
            currentTotalCount: currentTotalCount,
            targetCount: targetCount,
            countType: countType,
            appColors: appColors
        )
    }

    @ViewBuilder
    private var allDoneButton: some View {
        Button {
            onCompleteScan()
        } label: {
            VStack(spacing: 6) {
                Spacer()
                Image("all_done")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .overlay(appColors.primary)
                    .mask(Image("all_done").resizable().scaledToFit())

                Spacer().frame(height: 8)
                Text("All Done")
                    .foregroundStyle(appColors.text)
                    .font(.system(size: 16))
            }
        }
    }

    // MARK: - LOGIC
    private func handleCountChange() {
        guard !isPausedDueToInactivity else { return }

        if !isAnimating {
            isAnimating = true
        }

        stabilityWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            withAnimation {
                isAnimating = false
            }
        }

        stabilityWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}

// MARK: TOTAL COUNT VIEW
struct TotalCountView: View {
    
    let currentTotalCount: Int
    let targetCount: Int32?
    let countType: CountType
    let appColors: AppColors
    
    private var showTarget: Bool {
        countType == .FIXED && (targetCount ?? 0) > 0
    }

    var body: some View {
        
        VStack(spacing: 6) {

                Spacer()

            // Current Total
            Text("\(currentTotalCount)")
                .foregroundStyle(appColors.primary)
                .font(.system(size: showTarget ? 26 : 30, weight: .bold))

            // Divider
            if showTarget {
                Rectangle()
                    .fill(appColors.primary)
                    .frame(width: 65, height: 1.5)
            }

            // Target
            if showTarget {
                Text("\(targetCount ?? 0)")
                    .foregroundStyle(appColors.primary)
                    .font(.system(size: 20, weight: .bold))
            }

            if !showTarget {
                Spacer().frame(height: 10)
            }

            Text("Total Count")
                .foregroundStyle(appColors.text)
                .font(.system(size: 16))
                .padding(.top, 8)
        }
    }
}
// MARK: LIST BOTTOM
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
                .padding(.top, 60)
            }
        }
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

// MARK: - HEADER BOTTOM
struct BottomControlsViewHeader: View {
    let drugName: String
    let isLandScape: Bool
    @EnvironmentObject private var appColors: AppColors
    @Binding var isScanPill: Bool
    let onResetPills: () -> Void

    var body: some View {
        Group {
            if isLandScape {
                VStack(spacing: 2) {
                    Text(drugName)
                        .foregroundStyle(appColors.text)
                        .font(.system(size: 16))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                }
            } else {
                ZStack {
                    Text(drugName)
                        .foregroundStyle(appColors.text)
                        .font(.system(size: 16))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .center)

                }
            }
        }
    }

    private var resetButton: some View {
        Button {
            onResetPills()
        } label: {
            Image("delete")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .overlay(appColors.primary)
                .mask(Image("delete").resizable().scaledToFit())
        }
    }

    private var historyScanButton: some View {
        Button {
            isScanPill.toggle()
        } label: {
            let iconName = isScanPill ? "scan_pill" : "history_icon"

            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .overlay(appColors.primary)
                .mask(Image(iconName).resizable().scaledToFit())
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
    @State private var animationID = UUID()

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
                .id(animationID)
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

struct SuccessAnimationView: View {
    let count: Int
    let color: Color

    @State private var particles: [ConfettiParticle] = []
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // 1. Confetti Layer
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
            }

            // 2. Central Text Layer
            Text("+\(count)")
                .font(.system(size: 80, weight: .heavy))
                .foregroundStyle(color)
                .scaleEffect(scale)
                .opacity(opacity)
                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 0)
        }
        .onAppear {
            createParticles()
            animate()
        }
    }

    private func createParticles() {
        let colors: [Color] = [
            color, .red, .blue, .yellow, .green, .orange, .purple,
        ]
        for _ in 0..<50 {
            let angle = Double.random(in: 0..<360) * .pi / 180
            let speed = Double.random(in: 200...500)  // Explosion distance

            particles.append(
                ConfettiParticle(
                    x: UIScreen.main.bounds.width / 2,
                    y: UIScreen.main.bounds.height / 2,
                    vx: cos(angle) * speed,
                    vy: sin(angle) * speed,
                    color: colors.randomElement() ?? .blue,
                    size: CGFloat.random(in: 5...12),
                    opacity: 1.0
                )
            )
        }
    }

    private func animate() {
        // Animate Text
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            scale = 1.5
        }

        // Animate Particles
        withAnimation(.easeOut(duration: 1.5)) {
            for i in particles.indices {
                particles[i].x += particles[i].vx
                particles[i].y += particles[i].vy
                particles[i].opacity = 0
            }
        }

        // Fade out text at the end
        withAnimation(.easeIn(duration: 0.5).delay(2.0)) {
            opacity = 0
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    let color: Color
    let size: CGFloat
    var opacity: Double
}

// MARK: Vial
struct VialBottomContentView: View {

    let appColors: AppColors
    let isCaptured: Bool

    var onRedo: () -> Void
    var onCapture: () -> Void
    var onDone: () -> Void

    @Environment(\.isLandscape) private var isLandscape

    var body: some View {

        let layout = isLandscape
        ? AnyLayout(VStackLayout(spacing: 70))
        : AnyLayout(HStackLayout(spacing: 90))

        layout {

            // Redo
            VStack(spacing: 10) {
                Image("redo_icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isCaptured ? appColors.primary : appColors.primaryBackground)

                
                Text("Redo")
                    .font(.caption)
                    .foregroundColor(appColors.text )
            }
            .onTapGesture {
                guard isCaptured else { return }
                onRedo()
            }
            
            
            // Camera Button
            ZStack {
                Circle()
                    .fill(appColors.primary)
                    .frame(width: 70, height: 70)
                
                Image(systemName: "camera")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color.white)
            }
            .onTapGesture {
                onCapture()
            }
            
            
            // Done
            VStack(spacing: 10) {
                Image("done_icon")
                    .foregroundColor(isCaptured ? appColors.primary : .gray)

                Text("Done")
                    .font(.caption)
                    .foregroundColor(isCaptured ? appColors.text : .gray)
            }
            .onTapGesture {
                guard isCaptured else { return }
                onDone()
            }
        }
        .padding(.vertical, 25)
        .padding(.horizontal)
    }
}

// MARK: KEY VALUE INFO CARD
struct KeyValueInfoCard: View {
    
    let title: String
    let value: String
    
    @EnvironmentObject private var appColors: AppColors
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            // KEY (Label)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(appColors.text.opacity(0.8))
            
            // VALUE
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(appColors.text)
                .lineLimit(nil)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            appColors.inputBackground
                .opacity(appColors.isDarkMode ? 1 : 0.9)
        )
        .cornerRadius(12)
    }
}


struct MenuOption<Option: Hashable>: View {
    
    let options: [Option]
    @Binding var selectedOption: Option
    @Binding var isPresented: Bool
    
    let label: (Option) -> String
    let onSelect: (Option) -> Void
    
    @EnvironmentObject private var appColors: AppColors
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            
            Text("SELECT OPTIONS")
                .foregroundStyle(appColors.text)
                .font(.system(size: 18, weight: .bold))
            
            // 🔹 OPTIONS
            ForEach(options, id: \.self) { option in
                PillCountingRadioButton(
                    option: option,
                    selectedOption: $selectedOption,
                    label: label(option),
                    selectedColor: appColors.primary,
                    unselectedColor: .gray.opacity(0.5),
                    size: 20,
                    lineWidth: 2,
                    textColor: appColors.text
                )
                .padding(.vertical)
            }
            .padding(.horizontal)
            
            // 🔹 BUTTONS
            HStack {
                
                // CANCEL
                PillCountingButton(
                    iconName: nil,
                    title: "CANCEL",
                    textColor: appColors.text,
                    backgroundColor: appColors.primaryBackground,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: {
                        isPresented = false
                    }
                )
                
                // OK
                PillCountingButton(
                    iconName: nil,
                    title: "OK",
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 12, weight: .regular),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: {
                        isPresented = false
                        onSelect(selectedOption)
                    }
                )
            }
        }
        .frame(width: 250)
        .padding(.vertical)
    }
}

