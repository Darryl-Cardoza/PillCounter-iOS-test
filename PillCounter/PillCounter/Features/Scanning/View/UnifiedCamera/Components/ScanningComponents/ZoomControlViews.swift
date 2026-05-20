//
//  ZoomControlViews.swift
//  PillCounter
//

import SwiftUI

struct ZoomControlView: View {

    @ObservedObject var cameraService: CameraService
    @EnvironmentObject var appColors: AppColors

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 2.0

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Spacer()
                GeometryReader { geo in
                    let width = geo.size.width
                    let horizontalPadding: CGFloat = 16
                    let usableWidth = width - (horizontalPadding * 2)
                    let percentage = (cameraService.zoomFactor - minZoom) / (maxZoom - minZoom)
                    let thumbX = horizontalPadding + (usableWidth * percentage)

                    ZStack(alignment: .leading) {
                        Slider(
                            value: Binding(
                                get: { cameraService.zoomFactor },
                                set: { cameraService.setZoom($0); cameraService.resetInactivityTimer() }
                            ),
                            in: minZoom...maxZoom,
                            step: 0.1
                        )
                        .tint(appColors.secondary)

                        Text(String(format: "%.1fx", cameraService.zoomFactor))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(appColors.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .position(x: thumbX, y: -5)

                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard usableWidth > 0 else { return }
                                        let pct = min(max((value.location.x - horizontalPadding) / usableWidth, 0), 1)
                                        cameraService.setZoom(minZoom + (maxZoom - minZoom) * pct)
                                        cameraService.resetInactivityTimer()
                                    }
                            )
                    }
                }
                .frame(height: 60)
                .frame(height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 5)
            .cornerRadius(14)
        }
        .allowsHitTesting(!cameraService.isPausedDueToInactivity)
    }
}

struct ZoomControlViewVertical: View {

    @ObservedObject var cameraService: CameraService
    @EnvironmentObject var appColors: AppColors

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 2.0
    private let trackWidth: CGFloat = 2
    private let thumbSize: CGFloat = 22
    private let verticalPadding: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let height       = geo.size.height
            let usableHeight = height - (verticalPadding * 2)
            let percentage   = (cameraService.zoomFactor - minZoom) / (maxZoom - minZoom)
            let thumbY       = height - verticalPadding - (usableHeight * percentage)

            ZStack {
                Rectangle()
                    .fill(appColors.secondary)
                    .frame(width: trackWidth, height: usableHeight)
                    .position(x: geo.size.width / 2, y: height / 2)

                Text(String(format: "%.1fx", cameraService.zoomFactor))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .position(x: geo.size.width / 2 - 28, y: thumbY)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: geo.size.width / 2, y: thumbY)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard usableHeight > 0 else { return }
                                let pct = min(max((height - verticalPadding - value.location.y) / usableHeight, 0), 1)
                                cameraService.setZoom(minZoom + (maxZoom - minZoom) * pct)
                                cameraService.resetInactivityTimer()
                            }
                    )
            }
        }
        .frame(width: 44, height: 340)
        .allowsHitTesting(!cameraService.isPausedDueToInactivity)
    }
}
