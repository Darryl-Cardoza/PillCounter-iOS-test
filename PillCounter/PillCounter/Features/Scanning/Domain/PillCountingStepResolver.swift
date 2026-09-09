//
//  PillCountingStepResolver.swift
//  PillCounter
//
//  Created by Bhushan Patil on 13/03/26.
//


import Foundation

struct PillCountingStepResolver {

    static func getActiveSteps(
        txn: PillCountTransactionEntity? = nil
    ) -> [ControlledStep] {

        // No transaction yet — nothing is known about the flow (dispense vs
        // regular, drug schedule, etc.), so there's no real step list to return.
        // Falling through to the flow checks below would default into CONTROLLED
        // FLOW (since txn?.is_dispense is neither true nor false when txn is nil),
        // fabricating a plausible-looking but meaningless step list.
        guard let txn else { return [] }

        let drugType = DrugCatalogStore.shared.fetchById(txn.drug_id)?.drug_type


        let drugSchedule = DrugSchedule(rawValue: drugType ?? "")

        // ------ REGULAR COUNT FLOW -------
        if txn.is_dispense == false {
            return [
                .scan,
                .targetVerification
            ]
        }

        // -------- NON CONTROLLED FLOW --------
        if (txn.is_dispense == true) && drugSchedule == nil  {
            return [
                .scan,
                .targetVerification,
                .vial
            ]
        }
        

        // -------- CONTROLLED FLOW --------
        let backCountRequired = AppStorageManager.shared.isBackCountRequired
        let selectedSchedules = AppStorageManager.shared.selectedSchedules


        var steps: [ControlledStep] = [
            .scan,
            .containerInitiate,
            .targetVerification
        ]


        if let drugSchedule,
           selectedSchedules.contains(drugSchedule) {
           steps.append(.targetReverification)
        }
        
        steps.append(.vial)

        if backCountRequired {
            steps.append(.containerPending)
        }

        return steps
    }
}


extension PillCountingStepResolver {

    static func canProceedToDoubleCount(txn: PillCountTransactionEntity?) -> Bool {
        let steps = getActiveSteps(txn: txn)
        return steps.contains(.targetReverification)
    }

    static func canProceedToBackCount(txn: PillCountTransactionEntity?) -> Bool {
        let steps = getActiveSteps(txn: txn)
        return steps.contains(.containerPending)
    }
}
