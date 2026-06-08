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
                    await MainActor.run { showConfirmCompletionPopup = true }
                }
            },
            secondaryTitle: pillScanViewModel.currentTransaction?.is_from_pms == false ? L10n.Common.skip : nil,
            secondaryAction: pillScanViewModel.currentTransaction?.is_from_pms == false ? {
                showNoteOption = false
                pillScanViewModel.note = ""
                Task(priority: .background) {
                    await MainActor.run { showConfirmCompletionPopup = true }
                }
            } : {},
            onClose: {
                showNoteOption = false
                showConfirmCompletionPopup = false
            }
        )
    }

    var showConfirmCompletion: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.confirmCompletionTitle,
            message: L10n.PillCount.confirmCompletionMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: {
                showNoteOption = false
                showConfirmCompletionPopup = false
            },
            onConfirm: {
                showNoteOption = false
                showConfirmCompletionPopup = false

                // Capture before any state reset — startContinuousDispense() clears
                // currentTransaction, so read the id/type up front.
                let completedTxnId = pillScanViewModel.currentTransaction?.txn_id ?? 0
                let isFixed =
                    pillScanViewModel.currentTransaction?.count_type == CountType.FIXED.rawValue
                let completedCountType = router.selectedPillScanningType ?? .FIXED

                if isFixed {
                    // Continuous dispense — reset back to RX-scan in place and surface
                    // the "Today's Queue" sheet over it. No navigation. See UnifiedCameraView.
                    startContinuousDispense()
                } else {
                    stockCountViewModel.updateCounts(
                        txnId: completedTxnId,
                        bottleQty: nil,
                        looseQty: pillScanViewModel.addCurrentOpenPillCount
                    )
//                    router.setRoot(
//                        to: .authentication(.login(.dashboard(.pillCount(.stockCount))))
//                    )
                }
                Task(priority: .background) {
                    await userViewModel.completeTheSelectedTransaction(
                        txnId: completedTxnId,
                        countType: completedCountType
                    )
                }
            }
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

    var showStepCompletion: some View {
        ConfirmationDialogue(
            title: L10n.PillCount.confirmStepCompletionTitle,
            message: L10n.PillCount.confirmStepCompletionMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.ok,
            onCancel: { showStepCompletionPopup = false },
            onConfirm: {
                showStepCompletionPopup = false
                if pillScanViewModel.capturedVialImage != nil {
                    pillScanViewModel.capturedVialImage = nil
                    pillScanViewModel.vialCapturedImagePath = nil
                    cameraService.start()
                    cameraService.rebindPreviewLayer()
                    cameraService.resetInactivityTimer()
                }
                pillScanViewModel.handleStepCompletion()
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
