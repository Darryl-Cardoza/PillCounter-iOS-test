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
    
    // MARK: - Common Size Variables
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var iconSize: CGFloat { isIPad ? 32 : 40 }
    private var captureButtonSize: CGFloat { isIPad ? 100 : 70 }
    private var captureIconSize: CGFloat { isIPad ? 42 : 28 }
    private var captureIconWeight: Font.Weight { .medium }
    private var labelFont: Font { isIPad ? .title3 : .caption }
    private var layoutSpacing: CGFloat { isIPad ? 120 : (isLandscape ? 70 : 90) }

    var body: some View {
        // Redo / capture / done always sit in a horizontal row — at the bottom in
        // both orientations (landscape previously stacked them into a centered column).
        HStack(spacing: layoutSpacing) {
            VStack(spacing: 10) {
                Image("redo_icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(isCaptured ? appColors.primary : Color.white.opacity(0.5))
                Text(L10n.PillCount.redo)
                    .font(labelFont)
                    .foregroundColor(isCaptured ? appColors.text : Color.white.opacity(0.5))
            }
            .onTapGesture {
                guard isCaptured else { return }
                // Clearing the captured still removes the full-screen overlay and
                // reveals the live feed again. The session was never stopped, so no
                // restart/rebind is needed — just reset the inactivity timer.
                pillScanViewModel.capturedVialImage = nil
                pillScanViewModel.vialCapturedImagePath = nil
                cameraService.resetInactivityTimer()
                // Re-arm RX-label scanning so the operator can auto-capture again by
                // presenting the matching vial, in addition to the manual button.
                cameraService.resetBarcodeScanState()
                cameraService.enableBarcodeScanning()
            }

            ZStack {
                Circle()
                    .fill(appColors.primary)
                    .frame(width: captureButtonSize, height: captureButtonSize)
                Image(systemName: "camera")
                    .font(.system(size: captureIconSize, weight: captureIconWeight))
                    .foregroundColor(.white)
            }
            .onTapGesture { captureVial() }

            VStack(spacing: 10) {
                Image("done_icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundColor(isCaptured ? appColors.primary : Color.white.opacity(0.5) )
                Text(L10n.PillCount.done)
                    .font(labelFont)
                    .foregroundColor(isCaptured ? appColors.text : Color.white.opacity(0.5))
            }
            .onTapGesture {
                guard isCaptured else { return }
                doneVial()
            }
        }
        .padding(24)
        // Same translucent dark backdrop as the top / bottom bars.
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(16)
    }

    private func captureVial() {
        guard pillScanViewModel.capturedVialImage == nil else {
            pillScanViewModel.showToastMessage(text: L10n.PillCount.imageAlreadyCaptured)
            return
        }
        guard let image = cameraService.captureSnapshot() else { return }

        // Immediate shutter feedback — sound + haptic + a quick white flash — so the
        // capture feels instant even though saving the file happens just after.
        FeedbackManager.shared.playCameraShutterSound()
        FeedbackManager.shared.vibrate()
        withAnimation(.easeOut(duration: 0.08)) {
            pillScanViewModel.vialCaptureFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.18)) {
                pillScanViewModel.vialCaptureFlash = false
            }
        }

        // Do NOT stop the session — counting is already paused for the vial step. The
        // captured still is shown full-screen by UnifiedCameraLayout while
        // capturedVialImage is set; stopping would blank the live feed and cost a
        // restart on redo/done.
        let normalized = image.normalized()
        withAnimation(.easeInOut(duration: 0.2)) {
            pillScanViewModel.capturedVialImage = normalized
        }
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
