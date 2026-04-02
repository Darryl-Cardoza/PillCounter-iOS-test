//
//  HL7NotificationManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 06/02/26.
//

import Foundation
import UserNotifications

enum HL7NotificationManager {

    // Call once (App launch)
    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("[NOTIFICATION] Permission error:", error)
            } else {
                print("[NOTIFICATION] Permission granted =", granted)
            }
        }
    }

    static func show(
        title: String,
        body: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 0.5,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}



final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

