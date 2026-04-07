//
//  AppDelegate.swift
//  PillCounter
//
//  Created by Bhushan Patil on 07/04/26.
//
import UIKit
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("APNs Token received")

        // REQUIRED
        Messaging.messaging().apnsToken = deviceToken

        // FETCH FCM ONLY HERE
        Task {
            let token = await FCMManager.shared.getToken()
            print("FINAL FCM TOKEN:", token)
        }
    }
}
