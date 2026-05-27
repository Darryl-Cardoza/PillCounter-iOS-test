//
//  StockCountBatchBottomSheet.swift
//  PillCounter
//

import SwiftUI

// MARK: - Panel (list header + scrollable batch rows)

struct StockCountBatchPanel<BottomContent: View>: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    let topPadding: CGFloat
    let hideHeader: Bool
    let bottomContent: () -> BottomContent

    init(topPadding: CGFloat = 0, hideHeader: Bool = false, @ViewBuilder bottomContent: @escaping () -> BottomContent) {
        self.topPadding = topPadding
        self.hideHeader = hideHeader
        self.bottomContent = bottomContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────
            if !hideHeader {
                HStack(spacing: 8) {
                    Text("Batch Stock Count")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(appColors.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    scanPillsButton
                }
                .padding(.horizontal, 20)
                .padding(.top, topPadding + 16)
                .padding(.bottom, 12)
            }

            // ── RECENT BATCH COUNT label + search ────────────────
            HStack(spacing: 4) {
                Text(recentLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(appColors.text.opacity(0.4))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(appColors.primary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            // ── Scrollable list ──────────────────────────────────
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if stockCountViewModel.groupedTransactions.isEmpty {
                        emptyState
                    } else {
                        ForEach(stockCountViewModel.groupedTransactions, id: \.ndc) { txn in
                            countRow(txn)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            bottomContent()
        }
        .background(appColors.primaryBackground)
    }

    // MARK: Sub-views

    private var scanPillsButton: some View {
        Text("SCAN PILLS")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(appColors.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(appColors.primary, lineWidth: 1.5)
            )
            .fixedSize()
    }

    private var recentLabel: String {
        let n = stockCountViewModel.groupedTransactions.count
        return n > 0 ? "RECENT BATCH COUNT (\(n))" : "RECENT BATCH COUNT"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(appColors.text.opacity(0.2))
            Text("No items added yet")
                .font(.system(size: 13))
                .foregroundColor(appColors.text.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func countRow(_ txn: GroupedTransaction) -> some View {
        let isSelected = stockCountViewModel.selectedGroupedTransaction?.ndc == txn.ndc
        return BatchCountCard(txn: txn, isSelected: isSelected) {
            if isSelected {
                stockCountViewModel.selectedGroupedTransaction = nil
                stockCountViewModel.scannedDrugData = nil
            } else {
                stockCountViewModel.selectTransaction(txn)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}

// MARK: - Batch Count Card

struct BatchCountCard: View {

    @EnvironmentObject private var appColors: AppColors
    let txn: GroupedTransaction
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(txn.drugName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text)
                    .lineLimit(1)
                Text(txn.ndc)
                    .font(.system(size: 12))
                    .foregroundColor(appColors.text.opacity(0.48))
            }
            Spacer(minLength: 12)
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .center, spacing: 2) {
                    Text("\(txn.sealedBottleQty)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(appColors.secondary)
                    Text("Bottles")
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.4))
                }
                VStack(alignment: .center, spacing: 2) {
                    Text("\(txn.total)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(appColors.secondary)
                    Text("Pills")
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.4))
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(isSelected ? appColors.primary.opacity(0.1) : appColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? appColors.primary : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { onTap?() }
    }
}

// MARK: - Scanned Drug Details slot

struct ScannedDrugDetailsSlot: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    @Binding var containerStatus: StockCountOptionContainerStatus
    let onCancel: () -> Void
    let onAdd:    () -> Void
    var isEmbedded: Bool = false

    var body: some View {
        VStack(spacing: 24) {

            Text("SCANNED DRUG DETAILS")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            drugCard
                .padding(.horizontal, 20)

            actionButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.secondaryBackground)
        .modifier(BottomSheetStyle(enabled: !isEmbedded))
    }

    // ── Drug card ──────────────────────────────────────────────

    private var drugCard: some View {
        let drug       = stockCountViewModel.scannedDrugData
        let bucket     = stockCountViewModel.currentBatch?.bucket_id ?? "NORMAL"
        let packageQty = Int(drug?.quantity ?? 0)
        let adding     = stockCountViewModel.pendingBottleCount
        let existing   = stockCountViewModel.existingNdcBottleCount
        let newTotal   = existing + adding
        let totalPills = newTotal * packageQty

        return VStack(spacing: 24) {

            HStack(alignment: .top) {
                cellLabel("Drug Name", value: drug?.drugName ?? "—", color: appColors.secondary)
                Spacer()
                cellLabel("Bucket", value: bucket.uppercased(), color: appColors.text)
            }
            .padding(.vertical, 5)

            Divider()

            HStack(alignment: .top, spacing: 12) {
                cellLabel(
                    "NDC Number",
                    value: drug?.ndc ?? "—",
                    color: appColors.secondary
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                cellLabel(
                    "Batch No.",
                    value: drug?.lotNumber.isEmpty == false ? drug!.lotNumber : "—",
                    color: appColors.secondary
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                cellLabel(
                    "Expiry Date",
                    value: drug?.expiry.isEmpty == false ? drug!.expiry : "—",
                    color: appColors.secondary
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 5)

            bottleStepper(adding: adding, newTotal: newTotal, totalPills: totalPills, existing: existing)
                .padding(.vertical, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func cellLabel(
        _ label: String, value: String, color: Color,
        align: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: align, spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(appColors.text.opacity(0.42))
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }



    private func bottleStepper(adding: Int, newTotal: Int, totalPills: Int, existing: Int = 0) -> some View {
        HStack(spacing: 0) {

            // ── Minus button ──
            Button(action: {
                if stockCountViewModel.pendingBottleCount > 1 {
                    stockCountViewModel.pendingBottleCount -= 1
                }
            }) {
                Text("−")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundColor(
                        stockCountViewModel.pendingBottleCount > 1
                            ? appColors.primary
                            : appColors.primary.opacity(0.3)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            }
            .frame(width: 76)
            .background(appColors.primaryBackground)
            .clipShape(
                .rect(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: 14,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            

            // ── Center count card ──
            VStack(spacing: 2) {
                Text("\(newTotal)")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(appColors.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.25), value: newTotal)
                Text("\(totalPills) pills")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(appColors.text.opacity(0.4))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.25), value: totalPills)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(appColors.secondaryBackground)
            .overlay(
                Rectangle()
                    .stroke(appColors.primaryBackground, lineWidth: 4)
            )

            // ── Plus button ──
            Button(action: {
                stockCountViewModel.pendingBottleCount += 1
            }) {
                Text("+")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundColor(appColors.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 76)
            .background(appColors.primaryBackground)
            .clipShape(
                .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 14,
                    topTrailingRadius: 14,
                    style: .continuous
                )
            )
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private var actionButtons: some View {
        EqualWidthHStackButtons(spacing: 16) {
            PillCountingButton(
                iconName: nil, title: "CLEAR",
                textColor: appColors.primary, backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 14, weight: .bold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: onCancel
            )
            PillCountingButton(
                iconName: nil, title: "ADD",
                textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                font: .system(size: 14, weight: .bold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: onAdd
            )
        }
    }
}

// MARK: - Scanned Summary slot

struct ScannedSummarySlot: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    let onEndCount: () -> Void
    var isEmbedded: Bool = false

    var body: some View {
        let totalNdc  = stockCountViewModel.groupedTransactions.count
        let totalPill = stockCountViewModel.groupedTransactions.reduce(0) { $0 + Int($1.total) }

        return VStack(spacing: 16) {

            Text("SCANNED DRUG DETAILS")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top,  24)

            // ── Scan new bottle placeholder ──────────────────────
                VStack(spacing: 20) {
                    Image("placeholder_history")
                        .renderingMode(.template)
                        .foregroundColor(appColors.secondary)
                        .frame(width: 80, height: 80)
                    
                    Text("Scan a new Stock bottle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(appColors.text)
                }
            .padding(.horizontal, 20)
            .padding(.vertical, 60)


            Text("SCANNED SUMMARY")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total NDCs")
                        .font(.system(size: 14))
                        .foregroundColor(appColors.text)
                    Text("\(totalNdc)")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(appColors.text)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Pills")
                        .font(.system(size: 14))
                        .foregroundColor(appColors.text)
                    Text("\(totalPill)")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(appColors.secondary)
                }
                .padding(.leading, 20)
                Spacer()
                Button(action: onEndCount) {
                    Text("END COUNT")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(appColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.secondaryBackground)
        .modifier(BottomSheetStyle(enabled: !isEmbedded))
    }
}

// MARK: - Conditional bottom-sheet clip+shadow modifier

private struct BottomSheetStyle: ViewModifier {
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
    let onCancel:   () -> Void
    let onAdd:      () -> Void
    let onEndCount: () -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass)   private var vSizeClass

    private var isIPad: Bool { hSizeClass == .regular && vSizeClass == .regular }
    private var isLandscape: Bool { UIScreen.main.bounds.width > UIScreen.main.bounds.height }

    private var showDrugDetails: Bool { stockCountViewModel.scannedDrugData != nil }

    // Safe area top inset for status bar padding
    private var statusBarHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if isIPad && isLandscape {
                    iPadLandscapeLayout(size: geo.size)
                } else if isIPad {
                    iPadPortraitLayout(size: geo.size)
                } else {
                    iPhoneLayout(size: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(appColors.primaryBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    // ── iPad Landscape: side sheet from right — list TOP, details BOTTOM ──
    private func iPadLandscapeLayout(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // TOP — batch list with status-bar-aware top padding
            StockCountBatchPanel(topPadding: statusBarHeight) {
                EmptyView()
            }
            .frame(maxHeight: .infinity)


            

            // BOTTOM — drug details or summary
            if showDrugDetails {
                ScannedDrugDetailsSlot(
                    containerStatus: $containerStatus,
                    onCancel: onCancel,
                    onAdd: onAdd
                )
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
            } else {
                ScannedSummarySlot(onEndCount: onEndCount)
                    .environmentObject(appColors)
                    .environmentObject(stockCountViewModel)
            }
        }
    }

    // ── iPad Portrait: list LEFT / details RIGHT in a card ──
    private func iPadPortraitLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {

            // ── Full-width header ────────────────────────────────
            HStack(spacing: 8) {
                Text("Batch Stock Count")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(appColors.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                scanPillsButtonView
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // ── Two-column body ──────────────────────────────────
            HStack(spacing: 0) {
                StockCountBatchPanel(hideHeader: true) {
                    EmptyView()
                }
                .frame(width: size.width * 0.50)
                .frame(maxHeight: .infinity)

                // RIGHT — rounded card wrapping the detail/summary slot
                Group {
                    if showDrugDetails {
                        ScannedDrugDetailsSlot(
                            containerStatus: $containerStatus,
                            onCancel: onCancel,
                            onAdd: onAdd,
                            isEmbedded: true
                        )
                        .environmentObject(appColors)
                        .environmentObject(stockCountViewModel)
                    } else {
                        ScannedSummarySlot(onEndCount: onEndCount, isEmbedded: true)
                            .environmentObject(appColors)
                            .environmentObject(stockCountViewModel)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(appColors.secondaryBackground)
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                )
                .padding(.vertical, 16)
                .padding(.trailing, 16)
                .frame(width: size.width * 0.50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
    }

    // ── iPhone (portrait + landscape): drag pill + drug details or summary only ──
    private func iPhoneLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            dragPill
            if showDrugDetails {
                ScannedDrugDetailsSlot(
                    containerStatus: $containerStatus,
                    onCancel: onCancel,
                    onAdd: onAdd
                )
                .environmentObject(appColors)
                .environmentObject(stockCountViewModel)
            } else {
                ScannedSummarySlot(onEndCount: onEndCount)
                    .environmentObject(appColors)
                    .environmentObject(stockCountViewModel)
            }
            Spacer(minLength: 0)
        }
    }

    private var dragPill: some View {
        EmptyView()
    }

    private var scanPillsButtonView: some View {
        Text("SCAN PILLS")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(appColors.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(appColors.primary, lineWidth: 1.5)
            )
            .fixedSize()
    }
}
