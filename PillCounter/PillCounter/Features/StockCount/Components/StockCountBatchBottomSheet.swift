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
    let onCancel:    () -> Void
    let onAdd:       () -> Void
    let onEndCount:  () -> Void
    let onScanPills: () -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass)   private var vSizeClass

    @State private var showEditSheet = false

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
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if isIPad && isLandscape {
                    iPadLandscapeLayout
                } else if isIPad {
                    iPadPortraitLayout
                } else {
                    iPhoneLayout
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(appColors.primaryBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - iPad Landscape

    private var iPadLandscapeLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            StockCountBatchPanel(topPadding: statusBarHeight, onScanPills: onScanPills) {
                EmptyView()
            }
            .frame(maxHeight: .infinity)

            detailSlot(isIpadPortrait: false)
        }
    }

    // MARK: - iPad Portrait

    private var iPadPortraitLayout: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────
            HStack(spacing: 8) {
                Text("Batch Stock Count")
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
                    detailSlot(isIpadPortrait: true)
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
    }

    // MARK: - iPhone

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            detailSlot(isIpadPortrait: false)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared detail slot

    @ViewBuilder
    private func detailSlot(isIpadPortrait: Bool) -> some View {
        if showEditSheet, let txn = editableTxn {
            StockCountEditDetailsSheet(txn: txn, onDismiss: { showEditSheet = false })
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
        } else if showDrugDetails {
            ScannedDrugDetailsSlot(
                containerStatus: $containerStatus,
                onCancel: onCancel,
                onAdd: onAdd,
                onEditTapped: { showEditSheet = true },
                isIpadPortrait: isIpadPortrait
            )
            .environmentObject(appColors)
            .environmentObject(stockCountViewModel)
        } else {
            ScannedSummarySlot(onEndCount: onEndCount, isIpadPortrait: isIpadPortrait)
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
        }
    }

    // MARK: - Scan pills button

    private var scanPillsButtonView: some View {
        PillCountingButton(
            iconName: nil, title: "SCAN PILLS",
            textColor: appColors.primary, backgroundColor: .clear,
            borderColor: appColors.primary,
            font: .system(size: 11, weight: .bold),
            cornerRadius: 20, horizontalPadding: 14, verticalPadding: 10, iconSize: 0,
            action: onScanPills
        )
    }
}
