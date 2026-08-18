//
//  PillCounterApp.swift
//  PillCounter
//

import SwiftUI
import Firebase
import CoreData

@main
struct PillCounterApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var securityState = AppSecurityState()
    @ObservedObject private var sessionManager = SessionManager.shared

    // FIX F-09: Tracks whether a privacy overlay should be shown.
    @State private var isObscured: Bool = false

    @ObservedObject private var router               = Router()
    @ObservedObject private var loginViewModel       = LoginViewModel()
    @ObservedObject private var appColors            = AppColors.shared
    @ObservedObject private var confirmationDialogueManager = ConfirmationDialogueManager()
    @StateObject private var pillScanViewModel = PillScanViewModel()
    
    @StateObject private var userViewModel = UserViewModel()
    @StateObject private var stockCountViewModel = StockCountViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()
    @StateObject private var toastManager = ToastManager.shared
    @ObservedObject private var faceSessionManager = FaceSessionManager.shared

    private let isCompromised: Bool

    init() {
        _ = CoreDataManager.shared
        NSManagedObject.installEncryptionHooks()

        // Deferred from AppStorageManager.init: a fresh install wipes the
        // Keychain (and with it the field-encryption key), so any face rows
        // left on disk are undecryptable ciphertext. The purge needs the Core
        // Data stack, which only exists from the line above onwards.
        AppStorageManager.shared.purgeFaceEnrollmentsIfKeychainWasWiped()

        // Cold launch (app was fully closed, now reopened) always requires a
        // fresh face scan — never resume a session from a prior process.
        FaceSessionManager.shared.lockOnColdLaunch()

        let compromised = SecurityManager.isDeviceCompromised()
        self.isCompromised = compromised

        // FirebaseApp must be configured before any Firebase API is used.
        FirebaseApp.configure()

        UIApplication.shared.registerForRemoteNotifications()

        if !compromised {
            RuntimeUnit.activateIfNeeded()
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            #if DEBUG
            print("Notification permission granted:", granted)
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !securityState.isSecure {
                    SecurityViolationView()
                        .environmentObject(appColors)
                } else if userViewModel.isForceUpdate {
                    ForceUpdateView()
                        .environmentObject(appColors)
                } else if userViewModel.isMaintenance {
                    MaintenaceView()
                        .environmentObject(appColors)
                } else {
                    ZStack {
                        AppNavigation()
                            .font(.system(size: 16))
                            .environment(\.dynamicTypeSize, .medium)
                            .environmentObject(router)
                            .environmentObject(loginViewModel)
                            .environmentObject(userViewModel)
                            .environmentObject(appColors)
                            .environmentObject(confirmationDialogueManager)
                            .environmentObject(pillScanViewModel)
                            .environmentObject(stockCountViewModel)
                            .environmentObject(historyViewModel)
                            .environmentObject(toastManager)
                            .environmentObject(sessionManager)
                            .environmentObject(faceSessionManager)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in faceSessionManager.recordActivity() }
                            )
                            .onAppear { startSecurityMonitoring() }
                            .onChange(of: sessionManager.isSessionExpired) { _, expired in
                                if expired {
                                    AppLogoutManager.performLogout(
                                        userVM: userViewModel,
                                        pillScanVM: pillScanViewModel,
                                        loginViewModel: loginViewModel
                                    )
                                    router.navigationPath.removeLast(router.navigationPath.count)
                                    sessionManager.reset()
                                }
                            }
                            .task {
                                userViewModel.loadMobileThemeSettings()

                                // Hydrate the user from auth/me on launch (mirrors
                                // mobile settings). Forcing remote ensures the profile
                                // and terminal list are refreshed even when a stale
                                // local user already exists.
                                Task { await userViewModel.getUser(forceRemote: true) }

                                // Pharmacy type list is server-driven but static per
                                // session — fetch once at launch, not on every profile visit.
                                Task { await userViewModel.fetchPharmacyTypes() }

                                Task.detached(priority: .background) {
                                    await MainActor.run {
                                        HistoryCleanupStore.shared.cleanUpOldHistory()
                                    }
                                }

                                // Pre-warm all three CoreML models at launch so the
                                // first navigation to the camera screen doesn't hang.
                                // Each singleton loads its .mlpackage and compiles GPU
                                // shaders; doing this in the background avoids a visible
                                // stall when the camera view first appears.
                                Task.detached(priority: .background) {
                                    _ = PillDetector.shared         // pills_detector_fp16 (FP16, NeuralEngine)
                                    _ = TrayDetectionService.shared // tray_detector_fp16 (MobileNetV2-UNet segmentation, FP16)
                                    _ = GloveDetector.shared        // gloves_detector_fp32 (FP32, GPU)
                                }
                            }

                        if toastManager.isShowing {
                            VStack {
                                Spacer()
                                HStack(spacing: 10) {
                                    Image("icon_app")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                    Text(toastManager.message)
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(10)
                                .padding(.bottom, 32)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            .animation(.easeInOut, value: toastManager.isShowing)
                        }

                        if faceSessionManager.isOverlayVisible {
                            SessionLockOverlay()
                                .environmentObject(appColors)
                                .transition(.opacity)
                                .zIndex(1000)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: faceSessionManager.isOverlayVisible)
                }
            }
            .overlay(
                Group {
                    if isObscured {
                        Color(.systemBackground)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                }
            )
            .animation(.easeInOut(duration: 0.15), value: isObscured)
            .onAppear {
                if isCompromised {
                    securityState.isSecure = false
                }

                Hl7ServiceController.shared.bind(
                    pillScanViewModel: pillScanViewModel,
                    userViewModel: userViewModel
                )
                Hl7ServiceController.shared.evaluate()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
    }
}

// MARK: - SECURITY HANDLING
extension PillCounterApp {

    private func startSecurityMonitoring() {
        SecurityMonitor.shared.startMonitoring {
            DispatchQueue.main.async {
                securityState.isSecure = false
                SecurityMonitor.shared.stopMonitoring()
            }
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            //Remove the overlay once the app is visible again.
            isObscured = false
            if SecurityManager.isDeviceCompromised() {
                securityState.isSecure = false
            } else {
                startSecurityMonitoring()
            }
            Task { await sessionManager.checkTokenOnForeground() }
            // Face unlock is unusable with an empty roster — if the last
            // enrolled user was deleted (or removed while backgrounded), drop
            // the lock instead of stranding the app behind an unpassable scan.
            faceSessionManager.releaseLockIfNoUsersEnrolled()

        case .background:
            //Apply the overlay before iOS takes the snapshot.
            isObscured = true
            SecurityMonitor.shared.stopMonitoring()
            faceSessionManager.lockOnBackground()

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    private func initializeSecurityAndRuntime() {
        let compromised = SecurityManager.isDeviceCompromised()
        guard !compromised else {  
            securityState.isSecure = false
            return
        }
        RuntimeUnit.activateIfNeeded()
    }
}
    
