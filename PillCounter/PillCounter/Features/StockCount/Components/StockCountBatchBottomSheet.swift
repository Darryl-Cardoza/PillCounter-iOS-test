//
//  StockCountBatchBottomSheet.swift
//  PillCounter
//

import SwiftUI

// MARK: - Conditional bottom-sheet clip+shadow modifier

struct BottomSheetStyle: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .clipShape(RoundedCorners(radius: 24, corners: [.topLeft, .topRight]))
                .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: -6)
        } else {
            content
        }
    }
}

// MARK: - Full bottom sheet

struct StockCountBatchBottomSheet: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    @Binding var containerStatus: StockCountOptionContainerStatus
    @Binding var isExpanded: Bool
    /// Owned by the parent so a new barcode scan can force the edit sheet closed
    /// instead of leaving it open underneath the freshly scanned drug details.
    @Binding var showEditSheet: Bool
    let onPortraitDragChanged: (CGFloat) -> Void
    let onPortraitDragEnded: () -> Void
    let onLandscapeDragChanged: (CGFloat) -> Void
    let onLandscapeDragEnded: () -> Void
    let onCancel:    () -> Void
    let onAdd:       () -> Void
    let onEndCount:  () -> Void
    let onScanPills: () -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass)   private var vSizeClass

    private var isIPad: Bool { hSizeClass == .regular && vSizeClass == .regular }
    private var isLandscape: Bool { UIScreen.main.bounds.width > UIScreen.main.bounds.height }
    private var showDrugDetails: Bool { stockCountViewModel.scannedDrugData != nil }

    private var editableTxn: GroupedTransaction? {
        stockCountViewModel.selectedGroupedTransaction
            ?? stockCountViewModel.groupedTransactions.first(where: {
                $0.ndc == stockCountViewModel.scannedDrugData?.ndc
            })
    }

    private var statusBarHeight: CGFloat {
        safeAreaInsets.top
    }

    private var safeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets ?? .zero
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if isIPad && isLandscape {
                    iPadLandscapeLayout
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if isIPad {
                    iPadPortraitLayout
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if isLandscape {
                    // iPhone landscape: content has its own fixed full width so it
                    // doesn't compress — the BottomSheet frame + clipped() reveals it.
                    iPhoneLandscapeLayout
                } else {
                    // iPhone portrait: content has its own fixed full height so it
                    // doesn't compress — the BottomSheet frame + clipped() reveals it.
                    iPhoneLayout
                }
            }
        }
        .background(appColors.primaryBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - iPad Landscape

    @ViewBuilder
    private var iPadLandscapeLayout: some View {
        if showEditSheet, let txn = editableTxn {
            // Edit takes over the ENTIRE panel (full width + height).
            StockCountEditDetailsSheet(txn: txn, onDismiss: { showEditSheet = false })
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                StockCountBatchPanel(topPadding: statusBarHeight, onScanPills: onScanPills) {
                    EmptyView()
                }
                .frame(maxHeight: .infinity)

                detailSlot(isIpadPortrait: false)
            }
        }
    }

    // MARK: - iPad Portrait
    private var iPadPortraitLayout: some View {
        ZStack {
            // ── Base two-column sheet (dimmed while editing) ──────
            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────────
                HStack(spacing: 8) {
                    Text(L10n.StockCountSheet.batchStockCount)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(appColors.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    scanPillsButtonView.fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)

                // ── Two-column body ──────────────────────────────────
                HStack(alignment: .top, spacing: 0) {

                    // LEFT — raw list, no card background
                    StockCountBatchPanel(hideHeader: true, onScanPills: onScanPills) {
                        EmptyView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // RIGHT — detail slot in a card
                    Group {
                        iPadPortraitDetailSlot
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(appColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                    .padding(.leading, 4)
                    .padding(.trailing, 20)
                }
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appColors.primaryBackground)

            // ── Full-width bottom Edit card overlay ───────────────
            if showEditSheet, let txn = editableTxn {
                iPadPortraitEditOverlay(txn: txn)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showEditSheet)
    }

    /// Right-column detail slot for iPad portrait. Never hosts the edit
    /// sheet — editing is presented as a full-width bottom card overlay.
    @ViewBuilder
    private var iPadPortraitDetailSlot: some View {
        if showDrugDetails {
            ScannedDrugDetailsSlot(
                containerStatus: $containerStatus,
                onCancel: onCancel,
                onAdd: onAdd,
                onEditTapped: { showEditSheet = true },
                isIpadPortrait: true,
                applyBottomSheetStyle: false,
                isIPhone: false
            )
            .environmentObject(appColors)
            .environmentObject(stockCountViewModel)
        } else {
            ScannedSummarySlot(onEndCount: onEndCount, isIpadPortrait: true, applyBottomSheetStyle: false, isIPhone: false)
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
        }
    }

    /// Dimmed backdrop + full-width rounded Edit card docked at the bottom.
    private func iPadPortraitEditOverlay(txn: GroupedTransaction) -> some View {
        ZStack(alignment: .bottom) {
            // Dim the sheet behind the card. Tap-to-dismiss.
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { showEditSheet = false }

            StockCountEditDetailsSheet(txn: txn, onDismiss: { showEditSheet = false }, hugContentHeight: true)
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
                .frame(maxWidth: .infinity)
                // Hug content when short, but cap at 85% of the screen so a long
                // lot list scrolls internally instead of pushing the card past
                // the top/bottom of the screen.
                .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
                .background(appColors.primaryBackground)
                .clipShape(RoundedCorners(radius: 24, corners: [.topLeft, .topRight]))
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: -8)
                .transition(.move(edge: .bottom))
        }
    }

    // MARK: - iPhone Portrait
    // Full content is always rendered; the BottomSheet frame clips from below.
    // Dragging up grows the frame, revealing the list that sits below the details.

    private var iPhonePortraitDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in onPortraitDragChanged(v.translation.height) }
            .onEnded   { _ in onPortraitDragEnded() }
    }

    private var iPhoneLayout: some View {
        // Outer frame is set by the heightBinding in BottomSheet.
        // We give the VStack a fixed large intrinsic height so it never shrinks —
        // the sheet frame + clipped() acts as the reveal window.
        let fullHeight = UIScreen.main.bounds.height * 0.90

        return VStack(spacing: 0) {
            if showEditSheet {
                // ── Edit Details takes over the entire sheet — no header, no list ──
                detailSlot(isIpadPortrait: false, isIPhone: true, applyBottomSheetStyle: false)
            } else {
                // ── Header (drag target) ────────────────────────────
                HStack(spacing: 8) {
                    Text(L10n.StockCountSheet.batchStockCount)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(appColors.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    scanPillsButtonView.fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .contentShape(Rectangle())
                .gesture(iPhonePortraitDragGesture)

                // ── Drug detail card ────────────────────────────────
                Group {
                    detailSlot(isIpadPortrait: false, isIPhone: true, applyBottomSheetStyle: false)
                }
                .background(appColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .gesture(iPhonePortraitDragGesture)

                // ── List — always in layout below details, revealed when sheet expands ──
                StockCountBatchPanel(hideHeader: true, showScanPillsButton: false, onScanPills: onScanPills) {
                    EmptyView()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        // Anchor content to top so it never compresses — frame clips the bottom portion
        .frame(width: UIScreen.main.bounds.width, height: fullHeight, alignment: .top)
        .background(appColors.primaryBackground)
        .clipShape(RoundedCorners(radius: 24, corners: [.topLeft, .topRight]))
        .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: -6)
    }

    // MARK: - iPhone Landscape
    // Sheet slides in from the right; drag left expands, drag right collapses.
    // Full content rendered in a HStack; the BottomSheet frame clips from the right edge.

    private var iPhoneLandscapeDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in onLandscapeDragChanged(v.translation.width) }
            .onEnded   { _ in onLandscapeDragEnded() }
    }

    private var iPhoneLandscapeLayout: some View {
        let screenW        = UIScreen.main.bounds.width
        let screenH        = UIScreen.main.bounds.height
        // Full expanded width — full screen width (overlay now ignores safe area)
        let fullWidth      = screenW
        // Each column gets exactly half — equal left/right split
        let detailColWidth = fullWidth / 2
        let listColWidth   = fullWidth / 2

        return HStack(spacing: 0) {
            if showEditSheet {
                // ── Edit Details takes over the entire sheet — no header, no list ──
                detailSlot(isIpadPortrait: false, isIPhone: true, applyBottomSheetStyle: false)
                    .frame(width: fullWidth, height: screenH, alignment: .top)
                    .background(appColors.primaryBackground)
            } else {
                // ── Detail column — LEFT, fixed size, always fully visible ───────
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(L10n.StockCountSheet.batchStockCount)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(appColors.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        scanPillsButtonView.fixedSize()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    .contentShape(Rectangle())
                    .gesture(iPhoneLandscapeDragGesture)

                    Group {
                        detailSlot(isIpadPortrait: false, isIPhone: true, applyBottomSheetStyle: false)
                    }
                    .background(appColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 2)
                    .padding(.horizontal, 12)
                    .gesture(iPhoneLandscapeDragGesture)
                }
                .frame(width: detailColWidth, height: screenH, alignment: .top)
                .background(appColors.primaryBackground)

                // ── List — RIGHT, fixed size, clipped until widthBinding grows ──
                StockCountBatchPanel(hideHeader: true, showScanPillsButton: false, onScanPills: onScanPills) {
                    EmptyView()
                }
                .frame(width: listColWidth, height: screenH)
            }
        }
        // Total content is fullWidth wide, anchored to leading/top.
        // The BottomSheet frame (widthBinding) clips from the right — list hidden until expanded.
        // Do NOT apply clipShape here — BottomSheet.sheetView already clips with rounded corners.
        .frame(width: fullWidth, height: screenH, alignment: .leading)
        .background(appColors.primaryBackground)
    }

    // MARK: - Shared detail slot

    @ViewBuilder
    private func detailSlot(isIpadPortrait: Bool, isIPhone: Bool = false, applyBottomSheetStyle: Bool = true) -> some View {
        if showEditSheet, let txn = editableTxn {
            StockCountEditDetailsSheet(txn: txn, onDismiss: {
                // Animated so the sheet frame (grown/shrunk by onEditSheetChanged in the
                // parent) resizes in lockstep with this content swap instead of the two
                // visibly stepping apart — one instant, the other springing in later.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    showEditSheet = false
                }
            })
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
        } else if showDrugDetails {
            ScannedDrugDetailsSlot(
                containerStatus: $containerStatus,
                onCancel: onCancel,
                onAdd: onAdd,
                onEditTapped: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        showEditSheet = true
                    }
                },
                isIpadPortrait: isIpadPortrait,
                applyBottomSheetStyle: applyBottomSheetStyle,
                isIPhone: isIPhone
            )
            .environmentObject(appColors)
            .environmentObject(stockCountViewModel)
        } else {
            ScannedSummarySlot(onEndCount: onEndCount, isIpadPortrait: isIpadPortrait, applyBottomSheetStyle: applyBottomSheetStyle, isIPhone: isIPhone)
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
        }
    }

    // MARK: - Scan pills button
    private var scanPillsButtonView: some View {
        PillCountingButton(
            iconName: nil, title: L10n.StockCountSheet.scanPills,
            textColor: appColors.primary, backgroundColor: .clear,
            borderColor: appColors.primary,
            font: .system(size: 11, weight: .bold),
            cornerRadius: 20, horizontalPadding: 14, verticalPadding: 10, iconSize: 0,
            action: onScanPills
        )
    }
}
