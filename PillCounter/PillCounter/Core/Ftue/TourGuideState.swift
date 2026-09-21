//
//  TourGuideState.swift
//  PillCounter
//

import Foundation
import CoreGraphics

/// Holds the current tour's id, step list and progress. One instance lives
/// for the whole app (see FtueController) so progress survives navigation
/// between screens and rotation/config change, since it's never recreated by
/// a screen's body. Only one tour is ever configured/active at a time —
/// `configure(tourId:steps:)` swaps in a different screen's steps (and which
/// tourId's prefs to persist against) whenever no tour is currently active.
@MainActor
final class TourGuideState: ObservableObject {

    @Published private(set) var tourId: String = ""
    @Published private(set) var steps: [TourStep] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isActive: Bool = false

    /// Root-relative bounds of the currently-registered real targets, keyed
    /// by TourStep.id. Written by whichever tourTarget(_:) is on-screen.
    @Published var targetBounds: [String: CGRect] = [:]

    private let prefs: TourGuidePrefs

    init(prefs: TourGuidePrefs = .shared) {
        self.prefs = prefs
    }

    var currentStep: TourStep? {
        guard steps.indices.contains(currentIndex) else { return nil }
        return steps[currentIndex]
    }

    /// Replaces the tourId + step list. No-op while a tour is active so an
    /// in-flight tour's index (and prefs target) never gets invalidated out
    /// from under it — e.g. visiting a different screen mid-tour doesn't
    /// clobber the tour that's actually running.
    func configure(tourId: String, steps: [TourStep]) {
        guard !isActive else { return }
        self.tourId = tourId
        self.steps = steps
    }

    /// Whether this state is currently configured for the given tour — lets
    /// a screen check "is it my tour that's configured/resumable here" before
    /// calling configure/start, without clobbering a different tour that
    /// happens to be mid-run.
    func isConfigured(for tourId: String) -> Bool {
        self.tourId == tourId
    }

    func start() {
        guard !steps.isEmpty, !isActive else { return }
        if let savedId = prefs.currentStepId(tourId: tourId),
           let idx = steps.firstIndex(where: { $0.id == savedId }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
        isActive = true
        persistCurrentStep()
    }

    func next() {
        advance()
    }

    func back() {
        guard isActive, currentIndex > 0 else { return }
        currentIndex -= 1
        persistCurrentStep()
    }

    func dismiss() {
        guard isActive else { return }
        isActive = false
        prefs.saveCurrentStep(nil, tourId: tourId)
    }

    /// Called by business logic (e.g. after a real tap or scan) rather than
    /// by the overlay's own Next button. Only advances if `id` really is the
    /// step currently being shown, so a stray late callback can't skip ahead.
    func advanceIfCurrent(_ id: String) {
        guard isActive, currentStep?.id == id else { return }
        advance()
    }

    private func advance() {
        guard isActive else { return }
        if currentIndex + 1 < steps.count {
            currentIndex += 1
            persistCurrentStep()
        } else {
            isActive = false
            prefs.saveCurrentStep(nil, tourId: tourId)
        }
    }

    private func persistCurrentStep() {
        prefs.saveCurrentStep(currentStep?.id, tourId: tourId)
    }
}
