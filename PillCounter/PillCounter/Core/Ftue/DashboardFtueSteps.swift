//
//  DashboardFtueSteps.swift
//  PillCounter
//

import Foundation

enum DashboardFtueSteps {

    /// Matches the fixed id order in DashboardViewModel.statCards(iconColor:).
    /// These ids never depend on loaded data, so the step list can be built
    /// synchronously on first appearance rather than waiting on a data load.
    static let kpiCardIds = [
        "disp-high-priority",
        "disp-pending",
        "disp-cont-drugs",
        "disp-hazardous",
        "inv-cycle-count",
        "inv-pending-batch",
    ]

    static let pmsStatusId = "ftue.pmsStatus"
    static let stockCountId = "ftue.stockCount"
    static let dispenseEntryId = "ftue.dispenseEntry"

    static func kpiStepId(for cardId: String) -> String {
        "ftue.kpi.\(cardId)"
    }

    /// PMS status is excluded entirely when the pharmacy isn't PMS-integrated,
    /// since PMSConnectionButtonView doesn't render at all in that case and
    /// there would never be a target to spotlight.
    static func build(isPmsIntegrated: Bool) -> [TourStep] {
        var steps: [TourStep] = []

        if isPmsIntegrated {
            steps.append(
                TourStep(
                    id: pmsStatusId,
                    title: L10n.Ftue.PmsStatus.title,
                    description: L10n.Ftue.PmsStatus.description,
                    mode: .info
                )
            )
        }

        steps.append(
            TourStep(
                id: stockCountId,
                title: L10n.Ftue.StockCount.title,
                description: L10n.Ftue.StockCount.description,
                mode: .info
            )
        )

        for cardId in kpiCardIds {
            steps.append(
                TourStep(
                    id: kpiStepId(for: cardId),
                    title: L10n.Ftue.Kpi.title,
                    description: L10n.Ftue.Kpi.description,
                    mode: .info
                )
            )
        }

        steps.append(
            TourStep(
                id: dispenseEntryId,
                title: L10n.Ftue.DispenseEntry.title,
                description: L10n.Ftue.DispenseEntry.description,
                mode: .actionTap
            )
        )

        return steps
    }
}
