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
        
        let drugType = DrugCatalogStore.shared.fetchById(txn?.drug_id ?? 0)?.drug_type
        
        
        let drugSchedule = DrugSchedule(rawValue: drugType ?? "")
        
        // ------ REGULAR COUNT FLOW -------
        if txn?.is_dispense == false {
            return [
                .scan,
                .targetVerification
            ]
        }

        // -------- NON CONTROLLED FLOW --------
        if (txn?.is_dispense == true) && drugSchedule == nil  {
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
