//
//  FtueController.swift
//  PillCounter
//
//  App-wide singleton holding the one TourGuideState, mirroring the existing
//  Hl7ServiceController/TransactionStore singleton pattern. Shared across
//  every screen with a tour (Dashboard, Batch Stock Count, and later the
//  Dispense flow) so progress survives navigation/rotation/config change.
//  Only one tour is ever configured/active at a time — see
//  TourGuideState.configure(tourId:steps:).
//

import Foundation

enum FtueTourId {
    static let dashboard = "dashboard"
    static let stockCount = "stockCount"
    static let dispense = "dispense"
}

@MainActor
final class FtueController {
    static let shared = FtueController()

    let state = TourGuideState()

    private var hasConfiguredDashboardSteps = false
    private var hasConfiguredStockCountSteps = false
    private var hasConfiguredDispenseSteps = false

    private init() {}

    /// Builds the Dashboard step list once. Safe to call from every
    /// DashboardView.onAppear — only the first call actually builds the list;
    /// TourGuideState.configure itself additionally no-ops while a different
    /// tour is active, so this never clobbers a tour in progress elsewhere.
    func configureDashboardStepsIfNeeded(isPmsIntegrated: Bool) {
        guard !hasConfiguredDashboardSteps else { return }
        hasConfiguredDashboardSteps = true
        state.configure(tourId: FtueTourId.dashboard, steps: DashboardFtueSteps.build(isPmsIntegrated: isPmsIntegrated))
    }

    /// Starts the Dashboard tour if it hasn't been seen yet and this state is
    /// actually configured for it (guards against a stale call landing after
    /// configure() no-op'd because a different tour was active).
    func startDashboardTourIfNeeded() {
        guard state.isConfigured(for: FtueTourId.dashboard),
              !TourGuidePrefs.shared.hasSeen(tourId: FtueTourId.dashboard)
        else { return }
        state.start()
    }

    /// Builds the Batch Stock Count step list once. Safe to call from every
    /// appearance of that screen.
    func configureStockCountStepsIfNeeded() {
        guard !hasConfiguredStockCountSteps else { return }
        hasConfiguredStockCountSteps = true
        state.configure(tourId: FtueTourId.stockCount, steps: StockCountFtueSteps.build())
    }

    func startStockCountTourIfNeeded() {
        guard state.isConfigured(for: FtueTourId.stockCount),
              !TourGuidePrefs.shared.hasSeen(tourId: FtueTourId.stockCount)
        else { return }
        state.start()
    }

    /// Builds the Dispense flow step list once. Safe to call from every
    /// appearance of the dispense scan types on UnifiedCameraView.
    func configureDispenseStepsIfNeeded() {
        guard !hasConfiguredDispenseSteps else { return }
        hasConfiguredDispenseSteps = true
        state.configure(tourId: FtueTourId.dispense, steps: DispenseFtueSteps.build())
    }

    func startDispenseTourIfNeeded() {
        guard state.isConfigured(for: FtueTourId.dispense),
              !TourGuidePrefs.shared.hasSeen(tourId: FtueTourId.dispense)
        else { return }
        state.start()
    }
}
