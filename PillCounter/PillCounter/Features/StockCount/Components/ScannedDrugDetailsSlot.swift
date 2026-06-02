//
//  ScannedDrugDetailsSlot.swift
//  PillCounter
//

import SwiftUI

struct ScannedDrugDetailsSlot: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    @Binding var containerStatus: StockCountOptionContainerStatus
    let onCancel:      () -> Void
    let onAdd:         () -> Void
    let onEditTapped:  () -> Void
    let isIpadPortrait: Bool
    var applyBottomSheetStyle: Bool = true
    var isIPhone: Bool = false

    var body: some View {
        VStack(spacing: 16) {

            HStack(alignment: .center) {
                Text(L10n.StockCountSheet.scannedDrugDetails)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)

                PillCountingButton(
                    iconName: nil, title: L10n.StockCountSheet.edit,
                    textColor: appColors.primary, backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 4, verticalPadding: 4, iconSize: 0,
                    action: onEditTapped
                )
                .frame(maxWidth: 80)
            }
            .padding(.top, isIpadPortrait ? 8 : 14)

            drugCard

            actionButtons
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.secondaryBackground)
        .modifier(BottomSheetStyle(enabled: applyBottomSheetStyle && !isIpadPortrait))
    }

    // MARK: - Drug Card

    private var drugCard: some View {
        let drug  = stockCountViewModel.scannedDrugData
        let bucket = stockCountViewModel.currentBatch?.bucket_id ?? "NORMAL"
        let batchId = String(stockCountViewModel.currentBatch?.batch_id ?? 0)
        let packageQty = Int(drug?.quantity ?? 0)
        // After auto-add, pendingBottleCount reflects the committed bottle count.
        let newTotal   = stockCountViewModel.pendingBottleCount
        let totalPills = newTotal * packageQty

        return VStack(spacing: 16) {
            if isIpadPortrait {
                VStack(alignment: .leading, spacing: 16) {
                    cellLabel(L10n.StockCountSheet.drugName, value: drug?.drugName ?? "—", color: appColors.secondary, align: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    cellLabel(L10n.StockCountSheet.ndcNumber, value: drug?.ndc ?? "—", color: appColors.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    HStack(alignment: .top, spacing: 12) {
                        cellLabel(L10n.StockCountSheet.batchNo, value: batchId, color: appColors.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        cellLabel(L10n.StockCountSheet.expiryDate, value: drug?.expiry.isEmpty == false ? drug!.expiry : "—", color: appColors.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        cellLabel(L10n.StockCountSheet.bucket, value: bucket.uppercased(), color: appColors.secondary, align: .trailing)
                    }
                }
            } else {
                HStack(alignment: .top) {
                    cellLabel(L10n.StockCountSheet.drugName, value: drug?.drugName ?? "—", color: appColors.secondary)
                    Spacer()
                    cellLabel(L10n.StockCountSheet.bucket, value: bucket.uppercased(), color: appColors.secondary, align: .leading)
                }

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    cellLabel(L10n.StockCountSheet.ndcNumber, value: drug?.ndc ?? "—", color: appColors.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    cellLabel(L10n.StockCountSheet.batchNo, value: batchId, color: appColors.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    cellLabel(L10n.StockCountSheet.expiryDate, value: drug?.expiry.isEmpty == false ? drug!.expiry : "—", color: appColors.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 5)
            }

            bottleStepper(newTotal: newTotal, totalPills: totalPills)
                .padding(.vertical, isIPhone ? 0 : 6)
        }
    }

    private func cellLabel(_ label: String, value: String, color: Color, align: HorizontalAlignment = .leading) -> some View {
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

    // MARK: - Bottle Stepper

    private func bottleStepper(newTotal: Int, totalPills: Int) -> some View {
        HStack(spacing: 0) {
            stepperButton(label: "−", isEnabled: stockCountViewModel.pendingBottleCount > 1, leadingCorners: true) {
                if stockCountViewModel.pendingBottleCount > 1 {
                    stockCountViewModel.pendingBottleCount -= 1
                    stockCountViewModel.debouncedUpdateBottleCount(stockCountViewModel.pendingBottleCount)
                }
            }

            VStack(spacing: 2) {
                Text("\(newTotal)")
                    .font(.system(size: isIPhone ? 24 : 32, weight: .semibold))
                    .foregroundColor(appColors.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.25), value: newTotal)
                Text(String(format: L10n.StockCountSheet.pillsWithCount, totalPills))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(appColors.text.opacity(0.4))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.25), value: totalPills)
            }
            .frame(maxWidth: .infinity)
            .frame(height: isIPhone ? 72 : 100)
            .background(appColors.secondaryBackground)
            .overlay(Rectangle().stroke(appColors.primaryBackground, lineWidth: 4))

            stepperButton(label: "+", isEnabled: true, leadingCorners: false) {
                stockCountViewModel.pendingBottleCount += 1
                stockCountViewModel.debouncedUpdateBottleCount(stockCountViewModel.pendingBottleCount)
            }
        }
        .frame(height: isIPhone ? 72 : 100)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepperButton(label: String, isEnabled: Bool, leadingCorners: Bool, action: @escaping () -> Void) -> some View {
        StepperRepeatButton(
            label: label,
            isEnabled: isEnabled,
            leadingCorners: leadingCorners,
            background: appColors.primaryBackground,
            foreground: isEnabled ? appColors.primary : appColors.primary.opacity(0.3),
            action: action
        )
        .frame(width: 82)
        .background(appColors.primaryBackground)
        .clipShape(.rect(
            topLeadingRadius: leadingCorners ? 14 : 0,
            bottomLeadingRadius: leadingCorners ? 14 : 0,
            bottomTrailingRadius: leadingCorners ? 0 : 14,
            topTrailingRadius: leadingCorners ? 0 : 14,
            style: .continuous
        ))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        EqualWidthHStackButtons(spacing: 16) {
            PillCountingButton(
                iconName: nil, title: L10n.StockCountSheet.clear,
                textColor: appColors.primary, backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 14, weight: .bold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: onCancel
            )
            PillCountingButton(
                iconName: nil, title: L10n.StockCountSheet.add,
                textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                font: .system(size: 14, weight: .bold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: onAdd
            )
        }
    }
}
