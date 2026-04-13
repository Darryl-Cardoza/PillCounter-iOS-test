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
        
        let pillLocalDB = PillsDataLocalStorage.shared
        let drugType = pillLocalDB.fetchDrugById(txn?.drug_id ?? 0)?.drug_type
        
        
        let drugSchedule = DrugSchedule(rawValue: drugType ?? "")
        
        // ------ REGULAR COUNT FLOW -------
        if txn?.count_type == CountType.REGULAR.rawValue {
            return [
                .scan,
                .targetVerification
            ]
        }

        // -------- NON CONTROLLED FLOW --------
        if (txn?.count_type == CountType.FIXED.rawValue) && drugSchedule == nil  {
            return [
                .scan,
                .targetVerification,
                .vial
            ]
        }
        

        // -------- CONTROLLED FLOW --------
        let doubleCountRequired = AppStorageManager.shared.isDoubleCountRequired
        let backCountRequired = AppStorageManager.shared.isBackCountRequired
        let selectedSchedules = AppStorageManager.shared.selectedSchedules


        var steps: [ControlledStep] = [
            .scan,
            .containerInitiate,
            .targetVerification
        ]


        if doubleCountRequired,
           let drugSchedule,
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
