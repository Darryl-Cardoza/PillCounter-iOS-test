//
//  StockCountFtueSteps.swift
//  PillCounter
//

import Foundation

enum StockCountFtueSteps {
    static let scanContainerId = "ftue.stockCount.scanContainer"
    static let activeNdcCardId = "ftue.stockCount.activeNdcCard"
    static let counterId = "ftue.stockCount.counter"
    static let clearId = "ftue.stockCount.clear"
    static let addId = "ftue.stockCount.add"
    static let recentCountsId = "ftue.stockCount.recentCounts"
    static let editDetailsId = "ftue.stockCount.editDetails"
    static let scanPillsId = "ftue.stockCount.scanPills"
    static let endCountId = "ftue.stockCount.endCount"

    static func build() -> [TourStep] {
        [
            TourStep(
                id: scanContainerId,
                title: L10n.Ftue.StockCount.ScanContainer.title,
                description: L10n.Ftue.StockCount.ScanContainer.description,
                mode: .actionWait,
                pinnedEdge: .bottom
            ),
            TourStep(
                id: activeNdcCardId,
                title: L10n.Ftue.StockCount.ActiveNdcCard.title,
                description: L10n.Ftue.StockCount.ActiveNdcCard.description,
                mode: .info
            ),
            TourStep(
                id: counterId,
                title: L10n.Ftue.StockCount.Counter.title,
                description: L10n.Ftue.StockCount.Counter.description,
                mode: .info
            ),
            TourStep(
                id: clearId,
                title: L10n.Ftue.StockCount.Clear.title,
                description: L10n.Ftue.StockCount.Clear.description,
                mode: .info
            ),
            TourStep(
                id: addId,
                title: L10n.Ftue.StockCount.Add.title,
                description: L10n.Ftue.StockCount.Add.description,
                mode: .actionTap
            ),
            TourStep(
                id: recentCountsId,
                title: L10n.Ftue.StockCount.RecentCounts.title,
                description: L10n.Ftue.StockCount.RecentCounts.description,
                mode: .info
            ),
            TourStep(
                id: editDetailsId,
                title: L10n.Ftue.StockCount.EditDetails.title,
                description: L10n.Ftue.StockCount.EditDetails.description,
                mode: .actionTap
            ),
            TourStep(
                id: scanPillsId,
                title: L10n.Ftue.StockCount.ScanPills.title,
                description: L10n.Ftue.StockCount.ScanPills.description,
                mode: .actionTap
            ),
            TourStep(
                id: endCountId,
                title: L10n.Ftue.StockCount.EndCount.title,
                description: L10n.Ftue.StockCount.EndCount.description,
                mode: .actionTap
            ),
        ]
    }
}
