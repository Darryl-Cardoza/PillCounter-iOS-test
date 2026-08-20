//
//  MockIdTextRecognitionRepository.swift
//  PillCounterTests
//
//  Scriptable fake for IdCardAnalyzer tests — per-call results, delays, and
//  throws, so the analyzer's throttle/gate/watchdog/confirmation logic is
//  testable without Vision or a device.
//

import CoreVideo
import Foundation
@testable import PillCounter

final class MockIdTextRecognitionRepository: IdTextRecognitionRepositoryProtocol {

    enum ScriptedCall {
        case success([IdTextLine])
        case failure(Error)
        /// Simulates a call that never returns — used to test the watchdog.
        case hang
    }

    struct StubError: Error {}

    private let lock = NSLock()
    private var script: [ScriptedCall] = []
    private(set) var callCount = 0

    /// Blocks `recognizeText` until this is signalled, when the scripted call
    /// is `.hang` — lets a test control exactly when (or whether) the watchdog
    /// wins the race against a slow recognizer.
    let hangSemaphore = DispatchSemaphore(value: 0)

    init(script: [ScriptedCall] = []) {
        self.script = script
    }

    func enqueue(_ call: ScriptedCall) {
        lock.lock()
        script.append(call)
        lock.unlock()
    }

    func recognizeText(in pixelBuffer: CVPixelBuffer) throws -> [IdTextLine] {
        lock.lock()
        callCount += 1
        let call = script.isEmpty ? .success([]) : script.removeFirst()
        lock.unlock()

        switch call {
        case .success(let lines):
            return lines
        case .failure(let error):
            throw error
        case .hang:
            hangSemaphore.wait()
            return []
        }
    }
}

/// Minimal 1x1 BGRA buffer — the analyzer's tests never inspect frame
/// content, only that a `CVPixelBuffer` was handed through.
func makeDummyPixelBuffer() -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
    return pixelBuffer!
}
