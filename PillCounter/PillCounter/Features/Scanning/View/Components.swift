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
    @State private var isAutoOrManual: Bool = false // this variable is to handle the auto detection capture.
    @Environment(\.isLandscape) private var isLandscape

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
                        cameraService.start()
                    }
                    .onDisappear { cameraService.stop() }

                    DetectionOverlay(cameraService: cameraService)
                        .ignoresSafeArea()
                    //Toggle
//                    VStack {
//                        HStack {
//                            Spacer()
//                            
//                            PillCountingToggleButton(
//                                isOn: $isAutoOrManual,
//                                onColor: appColors.secondary,
//                                offColor: Color.black.opacity(0.5)
//                            )
//                            .padding(.trailing, 16)
//                            .padding(.top, 16)
//                        }
//                        
//                        Spacer()
//                    }
                    .padding(.top, isLandscape ? 0 : 30)

                    ZoomControlView(cameraService: cameraService)
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

                    let horizontalPadding: CGFloat = 16   // slider internal padding
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
                .frame(height: 60)                .frame(height: 60)                .frame(height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .cornerRadius(14)
            .padding(.bottom, 16)
        }
        .allowsHitTesting(!cameraService.isPausedDueToInactivity)
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

    var body: some View {
        VStack(spacing: 0) {

            BottomControlsViewHeader(
                drugName: pillScanViewModel.currentTransaction?.drug?.drug_name
                    ?? "",
                isLandScape: isLandscape,
                isScanPill: $showHistoryOrScanPillIcon,
                onResetPills: onReset
            )
            .padding()
            .padding(.top, isLandscape ? 0 : 10)

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
                        isPausedDueToInactivity: cameraService
                            .isPausedDueToInactivity,
                        isAddButtonDisabled: isAddButtonDisabled
                    )
                    .padding()
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

    // We use a UUID to force SwiftUI to recreate the view when animation state changes.
    // This prevents the "repeatForever" from getting stuck or not resetting correctly.
    @State private var animationID = UUID()
    @State private var trimValue: CGFloat = 1.0

    var body: some View {
        VStack(spacing: -20) {

            // Circle with animated stroke
            ZStack {
                Circle()
                    .trim(from: 0, to: trimValue)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(
                            lineWidth: ringLineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(90))  // Start at 6 o'clock
                    .frame(width: size, height: size)
                    .id(animationID)  // ⬅️ Critical for resetting animation cleanly
                    .onAppear {
                        updateAnimationState()
                    }
                    .onChange(of: isAnimating) { _, _ in
                        updateAnimationState()
                    }

                Text("\(count)")
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(textColor)
            }
            .opacity(isDisabled ? 0.5 : 1.0)

            // Add button
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
    }

    private func updateAnimationState() {
        // Regenerate ID to kill any existing animation context
        animationID = UUID()

        if isAnimating {
            // Start with empty circle
            trimValue = 0
            withAnimation(
                .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                trimValue = 1
            }
        } else {
            // Stop state: Full Circle Visible immediately
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

    var body: some View {
        Group {
            if isLandscape {
                // MARK: - LANDSCAPE LAYOUT
                // 1. Center: Add Button
                // 2. Below: Row with Total Count (Left) and All Done (Right)
                VStack(spacing: 20) {
                    addButton

                    HStack(alignment: .bottom) {
                        totalCountView
                        Spacer()
                        allDoneButton
                    }
                }
            } else {
                // MARK: - PORTRAIT LAYOUT
                // All three in one bottom-aligned row
                HStack(alignment: .bottom) {
                    totalCountView
                        .frame(maxWidth: .infinity, alignment: .leading)

                    addButton
                        .frame(maxWidth: .infinity)

                    allDoneButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal)
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
            ringLineWidth: 5,
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

                Spacer().frame(height: 10)

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

    var body: some View {
        VStack(spacing: 6) {

            if countType == .REGULAR {
                Spacer()
            }

            // Current Total
            Text("\(currentTotalCount)")
                .foregroundStyle(appColors.primary)
                .font(
                    .system(size: countType == .FIXED ? 26 : 30, weight: .bold))

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

            if countType == .REGULAR {
                Spacer().frame(height: 10)
            }

            // Label
            Text("Total Count")
                .foregroundStyle(appColors.text)
                .font(.system(size: 16))  // Changed to 16 to match "All Done" text
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
                    HStack {
                        resetButton
                        Spacer()
                        historyScanButton
                    }

                    Text(drugName)
                        .foregroundStyle(appColors.text)
                        .font(.system(size: 18))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 30)
                }

            } else {
                ZStack {
                    // Layer 1: The Text (Centered)
                    Text(drugName)
                        .foregroundStyle(appColors.text)
                        .font(.system(size: 20))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // Layer 2: The Buttons (Left & Right edges)
                    HStack {
                        resetButton
                        Spacer()
                        historyScanButton
                    }
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
