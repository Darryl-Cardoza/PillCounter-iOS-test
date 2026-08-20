//
//  IdCardAnalyzer.swift
//  PillCounter
//
//  Per-frame OCR orchestration: throttle, single-flight gate, watchdog,
//  two-frame confirmation. Ported from IdCardAnalyzer.kt (Android reference),
//  PDF417 branch removed — see
//  plans/face-auth/ocr/19-08-2026-12-31-ocr-id-scan.md §2.2 and
//  plans/face-auth/ocr/ID_SCAN_OCR_IMPLEMENTATION.md §4.
//
//  All mutable state (gate, candidates, token, timestamps) lives on one
//  private serial queue, so no locks are needed and no two frames are ever
//  in Vision at once. The callback is always delivered on the main queue.
//
//  Gate-release paths — ALL FOUR must exist, or the gate latches and the
//  camera streams forever with no frame ever analysed again:
//  1. Recognition returned, fired or not.
//  2. Recognizer threw.
//  3. Buffer/handler setup failed before recognition.
//  4. Watchdog at 2.5s.
//

import CoreVideo
import Foundation

final class IdCardAnalyzer {

    private let minIntervalMs: TimeInterval = 0.4
    private let recognizerTimeout: TimeInterval = 2.5
    private let minSuggestionsToFire = 2

    private let recognizer: IdTextRecognitionRepositoryProtocol
    private let queue = DispatchQueue(label: "ocr.idcardanalyzer.queue")

    private var isPaused = false
    private var isProcessing = false
    private var isReleased = false

    /// Guards a stale late completion from freeing a newer frame's gate or
    /// cancelling its watchdog.
    private var frameToken: Int = 0
    private var lastAttemptAt: TimeInterval = 0
    private var watchdogWorkItem: DispatchWorkItem?

    /// Last OCR-parsed candidate; must repeat on the next frame to fire.
    private var lastCandidate: IdCardName?
    /// Last OCR suggestion words; must repeat to fire when no pair was parsed.
    private var lastSuggestions: [String] = []

    init(recognizer: IdTextRecognitionRepositoryProtocol = IdTextRecognitionRepository.shared) {
        self.recognizer = recognizer
    }

    func pause() {
        queue.async { self.isPaused = true }
    }

    /// Clears both candidate buffers — a stale candidate pairing with the
    /// first frame after a pause would fire a false confirmation.
    func resume() {
        queue.async {
            self.isPaused = false
            self.isProcessing = false
            self.watchdogWorkItem?.cancel()
            self.watchdogWorkItem = nil
            self.lastAttemptAt = 0
            self.lastCandidate = nil
            self.lastSuggestions = []
        }
    }

    func close() {
        queue.async {
            guard !self.isReleased else { return }
            self.isReleased = true
            self.isPaused = true
            self.watchdogWorkItem?.cancel()
            self.watchdogWorkItem = nil
        }
    }

    /// Analyzes one frame. `onDetected` fires on the main queue, at most once
    /// per confirmed result, only after two agreeing frames (or two agreeing
    /// suggestion sets).
    func analyze(pixelBuffer: CVPixelBuffer, now: TimeInterval = Date().timeIntervalSince1970, onDetected: @escaping (IdScanResult) -> Void) {
        queue.async {
            guard !self.isReleased, !self.isPaused else { return }
            guard now - self.lastAttemptAt >= self.minIntervalMs else { return }
            guard !self.isProcessing else { return }

            self.isProcessing = true
            self.lastAttemptAt = now

            self.frameToken += 1
            let token = self.frameToken
            self.armWatchdog(token: token)

            do {
                let lines = try self.recognizer.recognizeText(in: pixelBuffer)
                self.handleRecognized(lines: lines, token: token, onDetected: onDetected)
            } catch {
                // Path 2: recognizer threw.
                self.finishFrame(token: token)
            }
        }
    }

    // MARK: - Gate / watchdog

    private func armWatchdog(token: Int) {
        watchdogWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Path 4: watchdog fires only if this frame's gate is still held.
            if self.frameToken == token, self.isProcessing {
                self.isProcessing = false
            }
        }
        watchdogWorkItem = item
        queue.asyncAfter(deadline: .now() + recognizerTimeout, execute: item)
    }

    /// Only touches shared state if no newer frame has taken over — a stale
    /// frame completing late must neither free a newer frame's gate nor
    /// cancel its watchdog.
    private func finishFrame(token: Int) {
        guard frameToken == token else { return }
        watchdogWorkItem?.cancel()
        isProcessing = false
    }

    // MARK: - Two-frame confirmation

    private func handleRecognized(lines: [IdTextLine], token: Int, onDetected: @escaping (IdScanResult) -> Void) {
        let parsed = IdNameParser.parse(lines)
        let suggestions = IdNameParser.candidateWords(lines)

        if let parsed, parsed == lastCandidate, !isPaused {
            fire(IdScanResult(name: parsed, suggestions: suggestions), onDetected: onDetected)
        } else if parsed == nil,
                  suggestions.count >= minSuggestionsToFire,
                  suggestions == lastSuggestions,
                  !isPaused {
            fire(IdScanResult(name: nil, suggestions: suggestions), onDetected: onDetected)
        } else {
            lastCandidate = parsed
            lastSuggestions = suggestions
        }

        // Path 1: recognition returned, fired or not.
        finishFrame(token: token)
    }

    private func fire(_ result: IdScanResult, onDetected: @escaping (IdScanResult) -> Void) {
        isPaused = true
        DispatchQueue.main.async {
            onDetected(result)
        }
    }
}
