//
//  DispenseFtueSteps.swift
//  PillCounter
//

import Foundation

enum DispenseFtueSteps {
    static let rxScanId = "ftue.dispense.rxScan"
    static let proceedRxId = "ftue.dispense.proceedRx"
    static let containerScanId = "ftue.dispense.containerScan"
    static let pillCountId = "ftue.dispense.pillCount"
    static let noteId = "ftue.dispense.note"

    static func build() -> [TourStep] {
        [
            TourStep(
                id: rxScanId,
                title: L10n.Ftue.Dispense.RxScan.title,
                description: L10n.Ftue.Dispense.RxScan.description,
                mode: .actionWait,
                pinnedEdge: .bottom
            ),
            TourStep(
                id: proceedRxId,
                title: L10n.Ftue.Dispense.ProceedRx.title,
                description: L10n.Ftue.Dispense.ProceedRx.description,
                mode: .actionTap
            ),
            TourStep(
                id: containerScanId,
                title: L10n.Ftue.Dispense.ContainerScan.title,
                description: L10n.Ftue.Dispense.ContainerScan.description,
                mode: .actionWait,
                pinnedEdge: .bottom
            ),
            TourStep(
                id: pillCountId,
                title: L10n.Ftue.Dispense.PillCount.title,
                description: L10n.Ftue.Dispense.PillCount.description,
                mode: .actionTap
            ),
            TourStep(
                id: noteId,
                title: L10n.Ftue.Dispense.Note.title,
                description: L10n.Ftue.Dispense.Note.description,
                mode: .actionTap
            ),
        ]
    }
}
