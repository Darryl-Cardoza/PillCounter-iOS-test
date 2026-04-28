//
//  FCMManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 07/04/26.
//

import Foundation
import FirebaseMessaging
import UIKit

class FCMManager {
    static let shared = FCMManager()

    private init() {}

    private var continuation: CheckedContinuation<String, Never>?

    var currentToken: String?

    // Called when token is received
    func updateToken(_ token: String) {
        currentToken = token
        continuation?.resume(returning: token)
        continuation = nil
    }

    // Wait for token if not available
    func getToken() async -> String {
        if let token = currentToken {
            return token
        }

        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }
}


