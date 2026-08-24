//
//  PMSConnectionInfoView.swift
//  PillCounter
//

import SwiftUI

/// Read-only diagnostics screen for the HL7/PMS network connection.
///
/// Shows this device's own listener address (so the PMS side knows where to dial in)
/// and the PMS's configured IP/port this device dials out to.
///
/// The device's IP can change at any time (Wi-Fi reconnect, DHCP renewal, restart),
/// so it is polled on a timer while this screen is visible rather than read once.
struct PMSConnectionInfoView: View {

    @EnvironmentObject private var appColors: AppColors

    @State private var deviceIPAddress: String?
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// Local to this screen only — a test result is a point-in-time reachability
    /// check, not persisted app state. Resets whenever the screen appears.
    private enum TestState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }
    @State private var testState: TestState = .idle

    private var listenerPort: UInt16 {
        Hl7ServiceController.shared.hl7Manager?.port ?? 2575
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            sectionHeader(L10n.Settings.deviceSectionTitle)
            infoRow(label: L10n.Settings.deviceIpAddressLabel, value: deviceIPAddress ?? L10n.Settings.ipAddressUnavailable)
            infoRow(label: L10n.Settings.deviceListenerPortLabel, value: String(listenerPort))

            Divider().background(appColors.primaryBackground)
            sectionHeader(L10n.Settings.pmsSectionTitle)
            infoRow(label: L10n.Settings.pmsIpAddressLabel, value: AppStorageManager.shared.pmsIpAddress ?? L10n.Settings.ipAddressUnavailable)
            infoRow(label: L10n.Settings.pmsPortLabel, value: AppStorageManager.shared.pmsPort.map(String.init) ?? L10n.Settings.ipAddressUnavailable)

            testConnectionSection

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, SafeAreaInsets.top + 60)
        .background(appColors.primaryBackground)
        .onAppear {
            deviceIPAddress = NetworkUtils.getLocalIPAddress()
            testState = .idle
        }
        .onReceive(refreshTimer) { _ in deviceIPAddress = NetworkUtils.getLocalIPAddress() }
    }

    private var testConnectionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PillCountingButton(
                    title: testState == .testing ? L10n.Settings.testingConnection : L10n.Settings.testConnection,
                    textColor: appColors.primaryBackground,
                    backgroundColor: testState == .testing ? appColors.primary.opacity(0.5) : appColors.primary,
                    cornerRadius: 8,
                    horizontalPadding: 18,
                    verticalPadding: 10,
                    action: runTestConnection,
                    width: 180
                )
                .fontWeight(.regular)
                .disabled(testState == .testing)

                if testState == .testing {
                    ProgressView().tint(appColors.text)
                }
            }

            statusIndicator
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch testState {
        case .idle, .testing:
            EmptyView()
        case .success:
            statusLED(color: .green, text: L10n.Settings.connectionSuccessful)
        case .failure(let reason):
            statusLED(color: .red, text: reason)
        }
    }

    private func statusLED(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .foregroundColor(appColors.text)
                .fontWeight(.regular)
        }
    }

    private func runTestConnection() {
        guard
            let host = AppStorageManager.shared.pmsIpAddress, !host.isEmpty,
            let rawPort = AppStorageManager.shared.pmsPort,
            let port = UInt16(exactly: rawPort)
        else {
            testState = .failure(L10n.Settings.pmsConnectionInfoMissing)
            return
        }

        testState = .testing
        Hl7ServiceManager.testConnection(host: host, port: port) { result in
            switch result {
            case .success:
                testState = .success
            case .failure(let reason):
                testState = .failure(reason)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundColor(appColors.text.opacity(0.6))
            .textCase(.uppercase)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(appColors.text)
            Spacer()
            Text(value)
                .foregroundColor(appColors.secondary)
                .textSelection(.enabled)
        }
    }
}
