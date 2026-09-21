//
//  TourGuidePrefs.swift
//  PillCounter
//
//  Thin wrapper over AppStorageManager for FTUE tours' persisted state.
//  Keyed by a stable tourId (e.g. "dashboard", "stockCount") so independent
//  tours never share a resume-step or "seen" flag. "Seen" is written only
//  once a given tour truly finishes (see TourGuideOverlay's completion
//  check), not on every dismiss/navigation.
//

import Foundation

struct TourGuidePrefs {
    static let shared = TourGuidePrefs()

    private let storage = AppStorageManager.shared

    func hasSeen(tourId: String) -> Bool {
        storage.ftueSeen(tourId: tourId)
    }

    func markSeen(tourId: String) {
        storage.setFtueSeen(true, tourId: tourId)
        storage.setFtueStepId(nil, tourId: tourId)
    }

    func currentStepId(tourId: String) -> String? {
        storage.ftueStepId(tourId: tourId)
    }

    func saveCurrentStep(_ id: String?, tourId: String) {
        storage.setFtueStepId(id, tourId: tourId)
    }
}
