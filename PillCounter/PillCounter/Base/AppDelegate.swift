//
//  AppDelegate.swift
//  PillCounter
//
//  Created by Bhushan Patil on 07/04/26.
//
import UIKit
import FirebaseMessaging
import Firebase

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

//    func application(
//        _ application: UIApplication,
//        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
//    ) -> Bool {
//
//        FirebaseApp.configure()
//
//        //  Notification permission FIRST
//        let center = UNUserNotificationCenter.current()
//        center.delegate = self
//
//        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
//            print("Permission granted:", granted)
//
//            DispatchQueue.main.async {
//                UIApplication.shared.registerForRemoteNotifications()
//            }
//        }
//
//        // 🔥 Firebase delegate
//        Messaging.messaging().delegate = self
//
//        return true
//    }
//
//    // APNS TOKEN RECEIVED
//    func application(
//        _ application: UIApplication,
//        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
//    ) {
//        print("APNs Token received")
//
//        Messaging.messaging().apnsToken = deviceToken
//    }
//
//    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
//        guard let token = fcmToken else { return }
//
//        print("FCM Token:", token)
//
//        //SAVE + RESUME ANY WAITERS
//        FCMManager.shared.updateToken(token)
//    }
}
