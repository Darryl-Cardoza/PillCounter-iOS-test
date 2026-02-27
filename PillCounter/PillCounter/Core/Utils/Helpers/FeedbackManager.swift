//
//  FeedbackManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/02/26.
//

import UIKit
import AudioToolbox

final class FeedbackManager {

    static let shared = FeedbackManager()

    private let impactGenerator = UIImpactFeedbackGenerator(style: .rigid)

    private init() {
        impactGenerator.prepare()
    }

    func vibrate() {
        impactGenerator.impactOccurred()
        impactGenerator.prepare()
    }

    func playShutterSound() {
        AudioServicesPlaySystemSound(1057)
    }

    func triggerDetectionFeedback(
        isHapticEnabled: Bool,
        isSoundEnabled: Bool
    ) {
        if isHapticEnabled {
            vibrate()
            print("Vibrate")
        }

        if isSoundEnabled {
            playShutterSound()
            print("Shutter sound")
        }
    }
}
