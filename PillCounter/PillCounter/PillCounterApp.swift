//
//  PillCounterApp.swift
//  PillCounter
//
//  Created by HC on 31/10/25.
//

import SwiftUI
import Firebase

@main
struct PillCounterApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // MARK: - ENVIRONMENT
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - APP STATE
    @StateObject private var securityState = AppSecurityState()

    @ObservedObject private var router = Router()
    @ObservedObject private var loginViewModel = LoginViewModel()
    @ObservedObject private var appColors = AppColors.shared
    @ObservedObject private var confirmationDialogueManager = ConfirmationDialogueManager()
    @StateObject private var pillScanViewModel = PillScanViewModel()
    
    @StateObject private var userViewModel = UserViewModel()
    @StateObject private var stockCountViewModel = StockCountViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()
    @StateObject private var toastManager = ToastManager()

    private let isCompromised: Bool

    init() {
        let compromised = SecurityManager.isDeviceCompromised()
        self.isCompromised = compromised

//        FirebaseApp.configure()
        UIApplication.shared.registerForRemoteNotifications()
        // Only bootstrap when secure
        if !compromised {
            RuntimeUnit.activateIfNeeded()
        }
        
        let center = UNUserNotificationCenter.current()
              center.delegate = NotificationDelegate.shared

              center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                  print("Notification permission granted:", granted)
              }

    }

    var body: some Scene {
        WindowGroup {
            Group {
                // 1️⃣ Security violation (highest priority)
                if !securityState.isSecure {
                    SecurityViolationView()
                        .environmentObject(appColors)
                    // 2️⃣ Force Update
                } else if userViewModel.isForceUpdate {
                    ForceUpdateView()
                        .environmentObject(appColors)

                    // 3️⃣ Maintenance Mode
                } else if userViewModel.isMaintenance {
                    MaintenaceView()
                        .environmentObject(appColors)

                    // 4️⃣ Normal App
                } else {
                    ZStack{
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
                            .onAppear {
                                startSecurityMonitoring()
                            }
                            .task {
                                userViewModel.loadMobileThemeSettings()

                                Task.detached(priority: .background) {
                                    await MainActor.run {
                                        HistoryCleanupStore.shared.cleanUpOldHistory()
                                    }
                                }

                                // Pre-warm CoreML models at launch so the first
                                // navigation to the camera screen doesn't hang.
                                Task.detached(priority: .background) {
                                    _ = PillDetector.shared
                                    _ = TrayDetectionService.shared
                                }
                            }
                        //show toast when succefully updated profile date
                        if toastManager.isShowing {
                            VStack {
                                Spacer()

                                HStack(spacing: 10) {
                                    Image("app_icon")
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
                    }
                }
            }
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
            if SecurityManager.isDeviceCompromised() {
                securityState.isSecure = false
            } else {
                startSecurityMonitoring()
            }
        case .background, .inactive:
            SecurityMonitor.shared.stopMonitoring()
        @unknown default:
            break
        }
    }

    private func initializeSecurityAndRuntime() {
        let compromised = SecurityManager.isDeviceCompromised()

        if !compromised {
            securityState.isSecure = false
            return
        }

        // Only bootstrap when environment is verified as secure
        RuntimeUnit.activateIfNeeded()
    }
}
    
