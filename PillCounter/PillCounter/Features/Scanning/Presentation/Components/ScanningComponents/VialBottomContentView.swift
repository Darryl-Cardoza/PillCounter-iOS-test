//
//  VialBottomContentView.swift
//  PillCounter
//

import SwiftUI

struct VialBottomContentView: View {

    @EnvironmentObject var appColors: AppColors
    @EnvironmentObject var pillScanViewModel: PillScanViewModel
    @EnvironmentObject var cameraService: CameraService

    @Environment(\.isLandscape) private var isLandscape

    private var isCaptured: Bool { pillScanViewModel.capturedVialImage != nil }

    var body: some View {
        let layout = isLandscape
            ? AnyLayout(VStackLayout(spacing: 70))
            : AnyLayout(HStackLayout(spacing: 90))

        layout {
            VStack(spacing: 10) {
                Image("redo_icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isCaptured ? appColors.primary : appColors.primaryBackground)
                Text(L10n.PillCount.redo)
                    .font(.caption)
                    .foregroundColor(appColors.text)
            }
            .onTapGesture {
                guard isCaptured else { return }
                pillScanViewModel.capturedVialImage = nil
                pillScanViewModel.vialCapturedImagePath = nil
                cameraService.start()
                cameraService.rebindPreviewLayer()
                cameraService.resetInactivityTimer()
            }

            ZStack {
                Circle().fill(appColors.primary).frame(width: 70, height: 70)
                Image(systemName: "camera").font(.system(size: 28, weight: .medium)).foregroundColor(.white)
            }
            .onTapGesture { captureVial() }

            VStack(spacing: 10) {
                Image("done_icon").foregroundColor(isCaptured ? appColors.primary : .gray)
                Text(L10n.PillCount.done)
                    .font(.caption)
                    .foregroundColor(isCaptured ? appColors.text : .gray)
            }
            .onTapGesture {
                guard isCaptured else { return }
                doneVial()
            }
        }
        .padding(.vertical, 25)
        .padding(.horizontal)
    }

    private func captureVial() {
        guard pillScanViewModel.capturedVialImage == nil else {
            pillScanViewModel.showToastMessage(text: L10n.PillCount.imageAlreadyCaptured)
            return
        }
        guard let image = cameraService.captureSnapshot() else { return }
        cameraService.stop()
        let normalized = image.normalized()
        pillScanViewModel.capturedVialImage = normalized
        if let path = PhotoFileManager.shared.saveImage(normalized) {
            pillScanViewModel.vialCapturedImagePath = path
        }
    }

    private func doneVial() {
        guard let imagePath = pillScanViewModel.vialCapturedImagePath else { return }
        pillScanViewModel.addOrReplaceVialTransactionDetail(imagePath: imagePath)
        pillScanViewModel.vialDoneTriggered = true
    }
}
