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
    let onScanPills: (() -> Void)?
    let bottomContent: () -> BottomContent

    init(topPadding: CGFloat = 0, hideHeader: Bool = false, onScanPills: (() -> Void)? = nil, @ViewBuilder bottomContent: @escaping () -> BottomContent) {
        self.topPadding = topPadding
        self.hideHeader = hideHeader
        self.onScanPills = onScanPills
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
            if stockCountViewModel.groupedTransactions.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(stockCountViewModel.groupedTransactions, id: \.ndc) { txn in
                            countRow(txn)
                        }
                    }
                }
            }

            bottomContent()
        }
        .background(appColors.primaryBackground)
    }

    // MARK: Sub-views

    private var scanPillsButton: some View {
        PillCountingButton(
            iconName: nil, title: "SCAN PILLS",
            textColor: appColors.primary, backgroundColor: .clear,
            borderColor: appColors.primary,
            font: .system(size: 11, weight: .bold),
            cornerRadius: 20, horizontalPadding: 14, verticalPadding: 7, iconSize: 0,
            action: { onScanPills?() }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func countRow(_ txn: GroupedTransaction) -> some View {
        let isSelected = stockCountViewModel.selectedGroupedTransaction?.ndc == txn.ndc
        return VStack(spacing: 0) {
            BatchCountCard(txn: txn, isSelected: isSelected) {
                if isSelected {
                    stockCountViewModel.selectedGroupedTransaction = nil
                    stockCountViewModel.scannedDrugData = nil
                } else {
                    stockCountViewModel.selectTransaction(txn)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
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

            HStack(alignment: .center, spacing: 0) {
                // Pills first
                VStack(alignment: .center, spacing: 2) {
                    Text("\(txn.total)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(appColors.secondary)
                        .monospacedDigit()
                    Text("Pills")
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.4))
                }
                .frame(width: 64)               // fixed — fits 4 digits comfortably

                // Bottles second
                VStack(alignment: .center, spacing: 2) {
                    Text("\(txn.sealedBottleQty)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(appColors.secondary)
                        .monospacedDigit()
                    Text("Bottles")
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.4))
                }
                .frame(width: 64)               // same fixed width
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(appColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 2)
        .selectableEffect(isSelected: isSelected, highlightColor: appColors.secondary)
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
    let isIpadPortrait: Bool

    var body: some View {
        VStack(spacing: 16) {                          // was 24

            Text("SCANNED DRUG DETAILS")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)

            drugCard

            actionButtons
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 20)                      // moved here — equal sides
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.secondaryBackground)
        .modifier(BottomSheetStyle(enabled: !isIpadPortrait))
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

        return VStack(spacing: 16) {

            if isIpadPortrait {
         

                // ── Portrait: NDC full width, then Batch No + Expiry Date side by side ──
                VStack(alignment: .leading, spacing: 16) {
                    
                    cellLabel("Drug Name", value: drug?.drugName ?? "—", color: appColors.secondary, align: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()

                    cellLabel(
                        "NDC Number",
                        value: drug?.ndc ?? "—",
                        color: appColors.secondary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    HStack(alignment: .top, spacing: 12) {
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
                        
                        cellLabel("Bucket", value: bucket.uppercased(), color: appColors.secondary, align: .trailing)
                    }
                }

            } else {
                HStack(alignment: .top) {
                    cellLabel("Drug Name", value: drug?.drugName ?? "—", color: appColors.secondary)
                    Spacer()
                    cellLabel("Bucket", value: bucket.uppercased(), color: appColors.secondary, align: .leading)
                }
                
                Divider()
                // ── Landscape: NDC + Batch No + Expiry Date all in one row ──
                HStack(alignment: .top, spacing: 12) {
                    cellLabel(
                        "NDC Number",
                        value: drug?.ndc ?? "—",
                        color: appColors.secondary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)   // gets 2x space

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
            }

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
            .frame(width: 82)
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
            .frame(width: 82)
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
                .padding(.top,  30)

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
    let onScanPills: () -> Void

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
            StockCountBatchPanel(topPadding: statusBarHeight, onScanPills: onScanPills) {
                EmptyView()
            }
            .frame(maxHeight: .infinity)


            // BOTTOM — drug details or summary
            if showDrugDetails {
                ScannedDrugDetailsSlot(
                    containerStatus: $containerStatus,
                    onCancel: onCancel,
                    onAdd: onAdd,
                    isIpadPortrait: false
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
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            // ── Two-column body ──────────────────────────────────
            HStack(alignment: .top, spacing: 0) {

                // LEFT — list panel (header suppressed, full height)
                StockCountBatchPanel(hideHeader: true, onScanPills: onScanPills) {
                    EmptyView()
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity)          // fills its half naturally
                .frame(maxHeight: .infinity)

                // RIGHT — drug details or summary card
                Group {
                    if showDrugDetails {
                        ScannedDrugDetailsSlot(
                            containerStatus: $containerStatus,
                            onCancel: onCancel,
                            onAdd: onAdd,
                            isIpadPortrait: true
                        )
                        .environmentObject(appColors)
                        .environmentObject(stockCountViewModel)
                    } else {
                        ScannedSummarySlot(onEndCount: onEndCount, isEmbedded: true)
                            .environmentObject(appColors)
                            .environmentObject(stockCountViewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(appColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                .padding(.leading, 8)               // small gap from left panel
                .padding(.trailing, 16)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
    }
    // ── iPhone (portrait + landscape): drag pill + drug details or summary only ──
    private func iPhoneLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            if showDrugDetails {
                ScannedDrugDetailsSlot(
                    containerStatus: $containerStatus,
                    onCancel: onCancel,
                    onAdd: onAdd,
                    isIpadPortrait: false
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
