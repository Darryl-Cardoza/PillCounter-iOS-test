//
//  FCMManager.swift
//  PillCounter
//

import Foundation
import FirebaseMessaging
import UIKit

class FCMManager {
    static let shared = FCMManager()
    private init() {}

    private var continuation: CheckedContinuation<String, Never>?

    // MARK: - Current token (in-memory only)
    private(set) var currentToken: String?

    // Tracks the last value that was actually sent in a network request.
    private var lastSentToken: String?

    // MARK: - Token update
    func updateToken(_ token: String) {
        currentToken = token
        continuation?.resume(returning: token)
        continuation = nil
    }

    // MARK: - Get token
    func getToken() async -> String {
        if let token = currentToken { return token }
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    // MARK: - Token if changed  (FIX 4.5)
    func tokenIfChanged() -> String? {
        guard let token = currentToken, token != lastSentToken else { return nil }
        return token
    }

    func markTokenSent() {
        lastSentToken = currentToken
    }
}
