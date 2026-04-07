//
//  FCMManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 07/04/26.
//

import Foundation
import FirebaseMessaging
import UIKit

final class FCMManager: NSObject {
    
    static let shared = FCMManager()
    
    private var continuation: CheckedContinuation<String, Never>?
    
    private override init() {
        super.init()
        Messaging.messaging().delegate = self
    }
    
    var currentToken: String? {
        UserDefaults.standard.string(forKey: "fcm_token")
    }
    
    // MARK: - Public async function
    func getToken() async -> String {
        
        // 1. If already stored → return immediately
        if let token = UserDefaults.standard.string(forKey: "fcm_token") {
            return token
        }
        
        // 2. Try direct fetch (fast path)
        if let token = try? await Messaging.messaging().token() {
            saveToken(token)
            return token
        }
        
        // 3. Wait for delegate callback
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
    
    private func saveToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "fcm_token")
    }
}

// MARK: - MessagingDelegate
extension FCMManager: MessagingDelegate {
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        
        guard let token = fcmToken else { return }
        
        print("FCM Token:", token)
        
        saveToken(token)
        
        // Resume async call if waiting
        continuation?.resume(returning: token)
        continuation = nil
    }
}




