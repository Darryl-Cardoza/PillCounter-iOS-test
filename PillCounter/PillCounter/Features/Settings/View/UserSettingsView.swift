//
//  UserSettingsView.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

struct UserSettingsView: View {
    
    
    // All persisted settings now live in SettingsViewModel — the single
    // source of truth for this screen.
    @StateObject private var settingsViewModel = SettingsViewModel()

    // UI State for popups / sub-screens
    @State private var showClearDataConfirmationPopup: Bool = false
    @State private var showResetHazardousTrayColorPopup: Bool = false
    @State private var activeSubScreen: SettingsSubScreen? = nil
    @State private var showTimeLimitPicker: Bool = false
    @State private var showSaveHistoryPicker: Bool = false
    @State private var showSchedulePicker: Bool = false

    // Sections expand independently — any number can be open at once.
    // First card starts expanded.
    @State private var expandedSections: Set<SettingsSection> = [.dispenseControlledDrug]

    #if DEBUG
    /// Drives the debug-only face-verification screen. Presented as a cover
    /// rather than a route so navigation state stays untouched by debug-only
    /// scaffolding.
    @State private var showDebugFaceVerify: Bool = false
    #endif

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    
    
    private var isPmsIntegrated: Bool {
        AppStorageManager.shared.isPmsIntegrated || AppStorageManager.shared.isStandalone
    }
    /// PMS-gated rows are disabled when PMS integration is off for this account.
    private var isPmsDisabled: Bool { !isPmsIntegrated }

    /// Surface the "feature not available" toast when a PMS-gated row is tapped.
    private func showFeatureUnavailableToast() {
        ToastManager.shared.show(message: L10n.Menu.featureNotAvailableMessage)
    }

    /// A live binding in DEBUG; an inert constant in release, so the cover
    /// modifier can stay unconditional in `body` (a `#if` around a modifier in
    /// a `some View` chain changes the returned type).
    private var debugFaceVerifyBinding: Binding<Bool> {
        #if DEBUG
        return $showDebugFaceVerify
        #else
        return .constant(false)
        #endif
    }



    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BaseView(
                    topRatio: 1.0,
                    topContent: {
                        userSettingsContent(geometry: geometry)
                    },
                    bottomContent: {
                        EmptyView()
                    },
                    headerActions: { EmptyView() },
                    showBackButton: true,
                    showHamburgerMenu: false,
                    title: L10n.Menu.settings
                )
            }
        }
        .overlay {
            if let screen = activeSubScreen {
                subScreenView(screen)
                    .transition(.move(edge: .trailing))
                    .zIndex(1000)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: activeSubScreen)
        .customPopup(isPresented: $showClearDataConfirmationPopup) {
            clearHistoryConfirmatioDialog
        }
        .customPopup(isPresented: $showResetHazardousTrayColorPopup) {
            resetHazardousTrayColorDialog
        }
        .sheet(isPresented: $showTimeLimitPicker) {
            FaceSessionTimeoutPickerView(settingsViewModel: settingsViewModel)
                .environmentObject(appColors)
        }
        .sheet(isPresented: $showSaveHistoryPicker) {
            SaveHistoryOptionPickerView(settingsViewModel: settingsViewModel)
                .environmentObject(appColors)
        }
        .sheet(isPresented: $showSchedulePicker) {
            DrugSchedulePickerView(settingsViewModel: settingsViewModel)
                .environmentObject(appColors)
        }
        .modifier(DebugFaceVerifyCover(isPresented: debugFaceVerifyBinding))
        .onAppear {
            // PMS off → the gated features are unavailable; reset them to their
            // defaults (off / empty) so a stale "on" value can't take effect.
            if isPmsDisabled {
                settingsViewModel.resetPmsGatedSettings()
            }
        }
    }

    private var resetHazardousTrayColorDialog: some View {
        ConfirmationDialogue(
            title: L10n.Settings.resetHazardousTrayColorTitle,
            message: L10n.Settings.resetHazardousTrayColorMessage,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes
        ) {
            showResetHazardousTrayColorPopup = false
        } onConfirm: {
            settingsViewModel.resetHazardousTrayColor()
            showResetHazardousTrayColorPopup = false
        }
    }

    private var clearHistoryConfirmatioDialog: some View {
        ConfirmationDialogue(
            title: L10n.Settings.clearHistoryTitle,
            message: L10n.Settings.clearHistoryMessage,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes
        ) {
            showClearDataConfirmationPopup = false
        } onConfirm: {
            showClearDataConfirmationPopup = false
            settingsViewModel.clearLocalData()
        }
    }
    
    private func userSettingsContent(geometry: GeometryProxy) -> some View {
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(SettingsSection.allCases) { section in
                    sectionCard(section)
                }

                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, 16)
        .background(appColors.secondaryBackground)
    }

    private func sectionCard(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(section)

            if expandedSections.contains(section) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionContent(section)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(appColors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(appColors.text.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: appColors.text.opacity(0.06), radius: 6, x: 0, y: 3)
    }

    private func sectionHeader(_ section: SettingsSection) -> some View {
        HStack(spacing: 10) {
            Text(section.title)
                .foregroundStyle(appColors.text)
                .font(.system(size: 16, weight: .bold))

            Spacer()

            Image(systemName: expandedSections.contains(section) ? "chevron.up" : "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(appColors.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedSections.contains(section) {
                    expandedSections.remove(section)
                } else {
                    expandedSections = [section]
                }
            }
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: SettingsSection) -> some View {
        switch section {
        case .general:
            generalSectionContent
        case .dispenseControlledDrug:
            dispenseControlledDrugSectionContent
        case .faceDetection:
            faceDetectionSectionContent
        case .voiceAndHapticFeedback:
            voiceAndHapticFeedbackSectionContent
        case .hazardousPillCounting:
            hazardousPillCountingSectionContent
        }
    }

    @ViewBuilder
    private var generalSectionContent: some View {
        // MARK: Pill Counting
        ToggleRowView(
            title: L10n.Settings.alwaysAskNotes,
            isOn: $settingsViewModel.isPillCountingEnabled,
            onColor: appColors.primary,
            horizontalPadding: 0,
            onToggle: { newValue in
                settingsViewModel.setPillCountingEnabled(newValue)
            }
        )

        settingsDivider

        // MARK: Save History
        SettingsDisclosureRow(
            title: L10n.Settings.saveHistory,
            subtitle: settingsViewModel.saveHistoryOption.displayText
        ) {
            showSaveHistoryPicker = true
        }

        settingsDivider

        SettingsDisclosureRow(title: L10n.Settings.clearLocalData) {
            showClearDataConfirmationPopup = true
        }

        if AppStorageManager.shared.useStaticPMSConnection {
            settingsDivider

            // MARK: PMS Configuration (read-only diagnostics)
            SettingsDisclosureRow(
                title: L10n.Settings.connectionInfo,
                isDisabled: isPmsDisabled
            ) {
                if isPmsDisabled {
                    showFeatureUnavailableToast()
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeSubScreen = .connectionInfo
                }
            }
        }
    }

    @ViewBuilder
    private var dispenseControlledDrugSectionContent: some View {
        HStack(spacing: 4) {
            Text(L10n.Settings.requireDoubleCount)
                .foregroundStyle(appColors.text)
                .font(.system(size: 14, weight: .regular))

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(Array(DrugSchedule.allCases.enumerated()), id: \.element.id) { index, schedule in
                    Text(schedule.rawValue)
                        .foregroundColor(
                            settingsViewModel.isScheduleSelected(schedule)
                            ? appColors.secondary
                            : appColors.text.opacity(0.35)
                        )
                        .font(.system(size: 13, weight: .regular))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .opacity(isPmsDisabled ? 0.6 : 1.0)
        .onTapGesture {
            if isPmsDisabled {
                showFeatureUnavailableToast()
                return
            }
            showSchedulePicker = true
        }

        settingsDivider

        // MARK: Back Count
        ToggleRowView(
            title: L10n.Settings.requireBackCount,
            isOn: $settingsViewModel.isBackCountRequired,
            onColor: appColors.primary,
            horizontalPadding: 0,
            isDisabled: isPmsDisabled,
            onDisabledTap: { showFeatureUnavailableToast() },
            onToggle: { newValue in
                settingsViewModel.setBackCountRequired(newValue)
            }
        )
    }

    @ViewBuilder
    private var faceDetectionSectionContent: some View {
        // MARK: Auto Lock Session
        SettingsDisclosureRow(title: L10n.Settings.autoLockSession) {
            showTimeLimitPicker = true
        }

        settingsDivider

        // MARK: Quick Access Users
        SettingsDisclosureRow(title: L10n.Menu.quickAccessUsers) {
            router.navigate(to: .authentication(.user(.userSettings(.quickAccessUsers))))
        }
    }

    @ViewBuilder
    private var voiceAndHapticFeedbackSectionContent: some View {
        // MARK: Speech Instruction
        ToggleRowView(
            title: L10n.Settings.voiceInstructions,
            isOn: $settingsViewModel.isSpeechEnabled,
            onColor: appColors.primary,
            horizontalPadding: 0,
            onToggle: { newValue in
                settingsViewModel.setSpeechEnabled(newValue)
            }
        )

        settingsDivider

        // MARK: Sound
        ToggleRowView(
            title: L10n.Settings.soundFeedback,
            isOn: $settingsViewModel.isSoundEnabled,
            onColor: appColors.primary,
            horizontalPadding: 0,
            onToggle: { newValue in
                settingsViewModel.setSoundEnabled(newValue)
            }
        )

        settingsDivider

        // MARK: Haptic
        ToggleRowView(
            title: L10n.Settings.hapticFeedback,
            isOn: $settingsViewModel.isHapticEnabled,
            onColor: appColors.primary,
            horizontalPadding: 0,
            onToggle: { newValue in
                settingsViewModel.setHapticEnabled(newValue)
            }
        )
    }

    @ViewBuilder
    private var hazardousPillCountingSectionContent: some View {
        // MARK: HAZARDOUS DRUG
        ToggleRowView(
            title: L10n.Settings.hazardousPillSetting,
            isOn: $settingsViewModel.isHazardousDrugSettingEnabled,
            onColor: appColors.primary,
            horizontalPadding: 0,
            isDisabled: isPmsDisabled,
            onDisabledTap: { showFeatureUnavailableToast() },
            onToggle: { newValue in
                settingsViewModel.setHazardousDrugSetting(newValue)
            }
        )

        settingsDivider

        // MARK: Hazardous Tray Color
        SettingsDisclosureRow(
            title: L10n.Settings.hazardousTrayColor,
            subtitle: settingsViewModel.hazardousTrayColor ?? "—",
            isDisabled: isPmsDisabled
        ) {
            if isPmsDisabled {
                showFeatureUnavailableToast()
                return
            }
            // Only offer to reset when a hazardous tray color is set.
            if settingsViewModel.hazardousTrayColor != nil {
                showResetHazardousTrayColorPopup = true
            }
        }
    }
    
    @ViewBuilder
    private func subScreenView(_ screen: SettingsSubScreen) -> some View {
        BaseView(
            topRatio: 1.0,
            topContent: {
                switch screen {
                case .connectionInfo:
                    PMSConnectionInfoView()
                }
            },
            bottomContent: { EmptyView() },
            headerActions: { EmptyView() },
            showBackButton: true,
            showHamburgerMenu: false,
            title: screenTitle(screen),
            backgroundColor: appColors.primaryBackground,
            onBack: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeSubScreen = nil
                }
            }
        )
    }

    private func screenTitle(_ screen: SettingsSubScreen) -> String {
        switch screen {
        case .connectionInfo: return L10n.Settings.connectionInfoScreenTitle
        }
    }

    private var settingsDivider: some View {
        Divider().background(appColors.text.opacity(0.12))
    }

}


/// Presents the debug face-verification screen. Real cover in DEBUG, a no-op
/// passthrough in release, so `body` needs no conditional compilation.
private struct DebugFaceVerifyCover: ViewModifier {

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        content.fullScreenCover(isPresented: $isPresented) {
            FaceAuthenticationView { userId, userName in
                Log("DEBUG VerifyFace: matched \(userName) (\(userId))")
                // Exercise the real unlock plumbing — session owner switch,
                // last_authenticated_at write, idle timer arming — not just
                // the detection pipeline.
                FaceSessionManager.shared.unlock(userId: userId, userName: userName)
            }
        }
        #else
        content
        #endif
    }
}

private func alignmentFor(_ index: Int) -> Alignment {
    switch index {
    case 0: return .leading
    case 1: return .center
    case 2: return .trailing
    default: return .leading
    }
}

/// Tappable row with a bold title and an optional secondary subtitle —
/// the disclosure-style pattern used for rows that open a picker/sub-screen.
struct SettingsDisclosureRow: View {

    let title: String
    var subtitle: String? = nil
    var isDisabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(AppColors.shared.text)
                .font(.system(size: 14, weight: .regular))

            Spacer(minLength: 8)

            if let subtitle {
                Text(subtitle)
                    .foregroundColor(AppColors.shared.secondary)
                    .font(.system(size: 13, weight: .regular))
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isDisabled ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct ToggleRowView: View {

    let title: String
    @Binding var isOn: Bool

    var onColor: Color = .pink
    var horizontalPadding: CGFloat = 16
    /// When true the row is grayed out, the toggle is inert, and a tap anywhere
    /// on the row routes to `onDisabledTap` instead of flipping the toggle.
    var isDisabled: Bool = false
    var onDisabledTap: (() -> Void)? = nil
    var onToggle: ((Bool) -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(Font.Weight.regular)
                .foregroundColor(AppColors.shared.text)
            Spacer()
            PillCountingToggleButton(
                isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        guard !isDisabled else { return }
                        isOn = newValue
                        onToggle?(newValue)
                    }
                ),
                onColor: onColor
            )
            .scaleEffect(0.8)
            // Block the toggle's own hit-testing when disabled so the row-level
            // tap below is what fires (showing the "not available" popup).
            .allowsHitTesting(!isDisabled)
        }
        .padding(.horizontal, horizontalPadding)
        .opacity(isDisabled ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if isDisabled { onDisabledTap?() }
        }
    }
}


