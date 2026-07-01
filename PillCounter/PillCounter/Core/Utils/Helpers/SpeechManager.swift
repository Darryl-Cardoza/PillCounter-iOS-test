//
//  SpeechManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 13/03/26.
//

import AVFoundation

final class SpeechManager {

    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    /// - Parameter force: when `true`, speak even if the global speech setting is
    ///   off (used for explicit user actions like tapping the current step).
    func speak(_ text: String, force: Bool = false) {

        guard force || AppStorageManager.shared.isSpeechEnabled else { return }

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.0

        synthesizer.speak(utterance)
    }
}
