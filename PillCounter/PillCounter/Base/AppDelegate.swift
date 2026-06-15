//
//  AppDelegate.swift
//  PillCounter
//

import UIKit
import FirebaseMessaging
import Firebase

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        Messaging.messaging().delegate = self
        return true
    }

    // MARK: - APNs token forwarding
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        #if DEBUG
        print("APNs token forwarded to Firebase Messaging")
        #endif
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
    
        #if DEBUG
        print("APNs registration failed:", error.localizedDescription)
        #endif
    }

    // MARK: - FCM token refresh
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        #if DEBUG
        print("FCM token refreshed")
        #endif
        FCMManager.shared.updateToken(token)
    }
}
