//
//  UnifiedCameraBarcodePopups.swift
//  PillCounter
//
//  Popup/sheet content for barcode-scan phase:
//  NDC equivalence, barcode not found, stock count details, QR info, NDC mismatch.
//

import SwiftUI

extension UnifiedCameraView {

    var hazardousTrayPopup: some View {
        ConfirmationDialogue(
            title: "\(pillScanViewModel.pendingHazardousTrayColor) Tray Detected",
            message: "Mark the \(pillScanViewModel.pendingHazardousTrayColor) tray as the hazardous tray? It will then be required for all hazardous drugs.",
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes,
            onCancel: {
                pillScanViewModel.dismissHazardousTrayPopup()
            },
            onConfirm: {
                pillScanViewModel.confirmHazardousTray()
            }
        )
    }

    var hazardousTraySubstitutePopup: some View {
        ConfirmationDialogue(
            title: "\(pillScanViewModel.pendingHazardousTrayColor) Tray Detected",
            message: "This \(pillScanViewModel.pendingHazardousTrayColor) tray doesn't match the saved hazardous tray. Substitute the hazardous tray with the \(pillScanViewModel.pendingHazardousTrayColor) tray?",
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.BarcodeScan.substitute,
            onCancel: {
                pillScanViewModel.dismissHazardousTraySubstitutePopup()
            },
            onConfirm: {
                pillScanViewModel.substituteHazardousTray()
            }
        )
    }

    var ndcEquivalencePopup: some View {
        ConfirmationDialogue(
            title: pillScanViewModel.isNdcEquivalent
                ? L10n.GenericEquivalent.doYouWantSubstitute
                : L10n.BarcodeScan.rescanRequired,
            message: pillScanViewModel.isNdcEquivalent
                ? L10n.GenericEquivalent.subtitle
                : L10n.BarcodeScan.ndcDoesNotMatch,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: pillScanViewModel.isNdcEquivalent
                ? L10n.BarcodeScan.substitute
                : L10n.BarcodeScan.rescan,
            showSingleConfirmButton: !pillScanViewModel.isNdcEquivalent,
            onCancel: {
                pillScanViewModel.showNdcEquivalencePopup = false
                restartFlow()
            },
            onConfirm: {
                if pillScanViewModel.isNdcEquivalent {
                    pillScanViewModel.showNdcEquivalencePopup = false
                    pillScanViewModel.showScannedDrugInfoPopoup = true
                } else {
                    restartFlow()
                }
            }
        )
    }

    var stockCountDetailsPopup: some View {
        VStack(spacing: 23) {
            ScrollView {
                VStack {
                    Text(L10n.BarcodeScan.qrScannedSuccessfully)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(appColors.text)
                }
                .padding(.top)
                VStack(spacing: 16) {
                    KeyValueInfoCard(title: L10n.BarcodeScan.ndcNumber, value: stockCountViewModel.scannedDrugData?.ndc ?? "")
                    KeyValueInfoCard(title: L10n.BarcodeScan.drugName, value: stockCountViewModel.scannedDrugData?.drugName ?? "")
                    KeyValueInfoCard(title: L10n.BarcodeScan.quantity, value: String(stockCountViewModel.scannedDrugData?.quantity ?? 0))
                }
                VStack(alignment: .leading) {
                    Text(L10n.BarcodeScan.selectContainerStatus)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(appColors.text)
                }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                SegmentedPillSelector(options: [.sealed, .opened], selected: $scannedBottleContainerStatus) { option in
                    switch option {
                    case .sealed: return L10n.BarcodeScan.sealed
                    case .opened: return L10n.BarcodeScan.opened
                    }
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            EqualWidthHStackButtons(spacing: 30) {
                PillCountingButton(
                    iconName: nil, title: L10n.Common.cancel,
                    textColor: appColors.primary, backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 20, iconSize: 0,
                    action: { stockCountViewModel.showStockCountScannedDetails = false; restartFlow() }
                )
                PillCountingButton(
                    iconName: nil, title: L10n.Common.add,
                    textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 20, iconSize: 0,
                    action: {
                        stockCountViewModel.showStockCountScannedDetails = false
                        if pillScanViewModel.selectedTransaction?.is_from_pms == true,
                           let txn = pillScanViewModel.selectedTransaction {
                            pillScanViewModel.updatePmsTxnCount(
                                txn: txn,
                                containerStatus: scannedBottleContainerStatus,
                                scannedQty: Int(stockCountViewModel.scannedDrugData?.quantity ?? 0)
                            )
                        } else {
                            handleStockCountAdd()
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var scannedQrPopup: some View {
        VStack(spacing: 23) {
            ScrollView {
                VStack {
                    Text(L10n.BarcodeScan.qrScannedSuccessfully)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(appColors.text)
                }
                .padding(.top)
                VStack(spacing: 16) {
                    KeyValueInfoCard(title: L10n.BarcodeScan.ndcNumber, value: pillScanViewModel.scannedRxData?.ndcNo ?? "-")
                    KeyValueInfoCard(title: L10n.BarcodeScan.drugName, value: pillScanViewModel.scannedRxData?.drugName ?? "-")
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            EqualWidthHStackButtons(spacing: 30) {
                PillCountingButton(
                    iconName: nil, title: L10n.Common.cancel,
                    textColor: appColors.primary, backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 20, iconSize: 0,
                    action: { pillScanViewModel.showScannedDrugInfoPopoup = false; restartFlow() }
                )
                PillCountingButton(
                    iconName: nil, title: L10n.BarcodeScan.proceed,
                    textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 20, iconSize: 0,
                    action: { pillScanViewModel.showScannedDrugInfoPopoup = false; handleSubstitute() }
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    var ndcMismatchPopup: some View {
        ConfirmationDialogue(
            title: L10n.BarcodeScan.incorrectNdc,
            message: L10n.BarcodeScan.incorrectNdcMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.BarcodeScan.rescan,
            showSingleConfirmButton: true,
            onCancel: { restartFlow() },
            onConfirm: { restartFlow() }
        )
    }

    var rxOnHoldPopup: some View {
        ConfirmationDialogue(
            title: L10n.BarcodeScan.rxOnHoldTitle,
            message: L10n.BarcodeScan.rxOnHoldMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.BarcodeScan.rescan,
            showSingleConfirmButton: true,
            onCancel: {
                pillScanViewModel.showRxOnHoldPopup = false
                restartFlow()
            },
            onConfirm: {
                pillScanViewModel.showRxOnHoldPopup = false
                restartFlow()
            }
        )
    }

}
