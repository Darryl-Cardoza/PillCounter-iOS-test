//
//  ControlledFlowConfig.swift
//  PillCounter
//
//  Created by Bhushan Patil on 05/03/26.
//

import Foundation

struct ControlledFlowConfig {

    static func activeSteps(
        txn: PillCountTransactionEntity? = nil
    ) -> [ControlledStep] {
        
        let pillLocalDB = PillsDataLocalStorage.shared
        let drugType = pillLocalDB.fetchDrugById(txn?.drug_id ?? 0)?.drug_type
        
        
        let drugSchedule = DrugSchedule(rawValue: drugType ?? "")

        // -------- NON CONTROLLED FLOW --------
        if txn?.is_controlled == nil || txn?.is_controlled == false  {
            let steps: [ControlledStep] = [
                .scan,
                .targetVerification
            ]
            return steps
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
