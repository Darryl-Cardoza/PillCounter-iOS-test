//
//  UnifiedCameraPillCountPopups.swift
//  PillCounter
//
//  Popup content for pill-count phase:
//  zero count, note entry, confirm completion, delete all, step completion,
//  count mismatch, transaction detail.
//

import SwiftUI

extension UnifiedCameraView {

    var showNoteOptionPopup: some View {
        NotePopupView(
            title: L10n.PillCount.addNote,
            showClose: false,
            text: $pillScanViewModel.note,
            errorMessage: errorMessageOfNote,
            primaryTitle: L10n.Common.save,
            primaryAction: {
                if pillScanViewModel.note.isEmpty {
                    errorMessageOfNote = L10n.PillCount.pleaseAddNote
                    return
                }
                showNoteOption = false
                Task(priority: .background) {
                    pillScanViewModel.updateNoteForCurrentTransaction(
                        txn_id: pillScanViewModel.currentTransaction?.txn_id ?? 0,
                        note: pillScanViewModel.note
                    )
                    await MainActor.run { onComplete() }
                }
            },
            secondaryTitle: L10n.Common.skip,
            secondaryAction: {
                showNoteOption = false
                pillScanViewModel.note = ""
                Task(priority: .background) {
                    await MainActor.run { onComplete() }
                }
            },
            onClose: {
                showNoteOption = false
            }
        )
    }

    /// Back count has nothing left to scan (remaining == 0). Skip-only by design —
    /// the step is unreachable, so a cancel would just strand the transaction.
    var skipBackCountPopup: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.skipStepTitle,
            message: L10n.PillCount.skipStepMessage,
            cancelButtonText: "",
            confirmButtonText: L10n.Common.skip,
            showSingleConfirmButton: true,
            onCancel: {},
            onConfirm: {
                pillScanViewModel.showSkipBackCountPopup = false
                finishTransaction()
            }
        )
    }

    var showAddBottlePopupContent: some View {
        ConfirmationDialogue(
            title: L10n.BarcodeScan.addBottleTitle,
            message: L10n.BarcodeScan.addBottleMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: { pillScanViewModel.cancelAddBottle() },
            onConfirm: { pillScanViewModel.confirmAddBottle() }
        )
    }

    var showReplaceBottlePopupContent: some View {
        ConfirmationDialogue(
            title: L10n.BarcodeScan.replaceBottleTitle,
            message: L10n.BarcodeScan.replaceBottleMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: { pillScanViewModel.cancelReplaceBottle() },
            onConfirm: { pillScanViewModel.confirmReplaceBottle() }
        )
    }

    var deleteAllTransactionDetailsPopup: some View {
        VStack(spacing: 20) {
            Text(L10n.PillCount.confirmDeletion)
                .foregroundStyle(appColors.text).font(.headline)
            Text(L10n.PillCount.deleteAllTransactionsMessage)
                .foregroundStyle(appColors.text).multilineTextAlignment(.center).padding(.horizontal)
            HStack {
                PillCountingButton(
                    iconName: nil, title: L10n.Common.no,
                    textColor: appColors.primary, backgroundColor: .clear, borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 18, iconSize: 0,
                    action: { showDeleteAllTransactionDetailsPopup = false }
                )
                PillCountingButton(
                    iconName: nil, title: L10n.Common.yes,
                    textColor: .white, backgroundColor: appColors.primary, borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 18, iconSize: 0,
                    action: {
                        showDeleteAllTransactionDetailsPopup = false
                        pillScanViewModel.deleteAllDetailsOfCurrentTransaction()
                    }
                )
            }
        }
    }

    var resetTransactionPopup: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.confirmResetTitle,
            message: L10n.PillCount.confirmResetMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: { showResetTransactionPopup = false },
            onConfirm: {
                showResetTransactionPopup = false
                if isOpenPillScanMode {
                    resetOpenPillScanInPlace()
                } else {
                    resetTransactionInPlace()
                }
            }
        )
    }

    var countMismatchDialog: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.countMismatchTitle,
            message: L10n.PillCount.countMismatchMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: { showCountMismatchPopup = false },
            onConfirm: {
                showNoteOption = true
                showCountMismatchPopup = false
            }
        )
    }

//    var showTransactionDetail: some View {
//        VStack(spacing: 35) {
//            HStack {
//                Text(String(format: L10n.PillCount.transactionDetail, selectedTransactionDetail?.txn_details_id ?? 0))
//                Spacer()
//                Button {
//                    showTransactionDetailPopup = false
//                    selectedTransactionDetail = nil
//                } label: {
//                    Image(systemName: "xmark")
//                        .resizable().scaledToFit().frame(width: 16, height: 16)
//                        .foregroundStyle(appColors.text)
//                }
//            }
//            HStack(spacing: 30) {
//                if let image = selectedTransactionDetail?.image_path,
//                   let loadedImage = PhotoFileManager.shared.loadImage(from: image) {
//                    loadedImage.resizable().scaledToFill()
//                        .frame(width: 140, height: 120).clipped().cornerRadius(12)
//                } else {
//                    RoundedRectangle(cornerRadius: 12)
//                        .stroke(appColors.text.opacity(0.5), lineWidth: 1)
//                        .frame(width: 100, height: 80)
//                }
//                VStack(spacing: 10) {
//                    Text(L10n.PillCount.header).foregroundStyle(appColors.primary)
//                    CircleBadge(
//                        size: 50, strokeWidth: 0, outerColor: .clear,
//                        innerColor: appColors.secondary,
//                        text: "\(selectedTransactionDetail?.pill_count ?? 0)",
//                        textColor: .white,
//                        font: .system(size: 18, weight: .bold),
//                        isAnimated: false
//                    )
//                    Text(
//                        "\(Formatter.getDateString(from: selectedTransactionDetail?.created_at ?? 0)) "
//                            + "\(Formatter.getTimeString(from: selectedTransactionDetail?.created_at ?? 0))"
//                    )
//                    .foregroundStyle(appColors.text).font(.system(size: 14))
//                }
//            }
//            HStack {
//                PillCountingButton(
//                    iconName: nil, title: L10n.Common.delete,
//                    textColor: appColors.primary, backgroundColor: .clear, borderColor: appColors.primary,
//                    font: .system(size: 12, weight: .semibold),
//                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 18, iconSize: 0,
//                    action: {
//                        showTransactionDetailPopup = false
//                        pillScanViewModel.softDeleteCurrentTransactionSelectedTransactionDetail(
//                            txnDetailId: selectedTransactionDetail?.txn_details_id ?? 0
//                        )
//                    }
//                )
//                PillCountingButton(
//                    iconName: nil, title: L10n.Common.ok,
//                    textColor: .white, backgroundColor: appColors.primary, borderColor: appColors.primary,
//                    font: .system(size: 12, weight: .semibold),
//                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 18, iconSize: 0,
//                    action: { showTransactionDetailPopup = false }
//                )
//            }
//        }
//        .frame(width: 300)
//    }
}
