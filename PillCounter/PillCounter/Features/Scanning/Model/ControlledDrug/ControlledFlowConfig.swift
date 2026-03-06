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

        print("🔍 ControlledFlowConfig.activeSteps called")

        if let txn {
            print("📦 Transaction id: \(txn.txn_id)")
            print("💊 is_controlled: \(txn.is_controlled)")
        } else {
            print("⚠️ Transaction is nil")
        }

        // -------- NON CONTROLLED FLOW --------
        if txn?.is_controlled == nil || txn?.is_controlled == false  {

            print("➡️ Non-controlled flow selected")
            let steps: [ControlledStep] = [
                .scan,
                .targetVerification
            ]

            print("📋 Steps: \(steps.map { $0.rawValue })")

            return steps
        }

        // -------- CONTROLLED FLOW --------
        let doubleCountRequired = AppStorageManager.shared.isDoubleCountRequired
        let backCountRequired = AppStorageManager.shared.isBackCountRequired

        print("🔐 Controlled flow selected")
        print("🔁 Double count required: \(doubleCountRequired)")
        print("📦 Back count required: \(backCountRequired)")

        var steps: [ControlledStep] = [
            .scan,
            .containerInitiate,
            .targetVerification
        ]

        if doubleCountRequired {
            print("➕ Adding TARGET_REVERIFICATION step")
            steps.append(.targetReverification)
        }

        print("📸 Adding VIAL step")
        steps.append(.vial)

        if backCountRequired {
            print("➕ Adding CONTAINER_PENDING step")
            steps.append(.containerPending)
        }

        print("📋 Final Steps: \(steps.map { $0.rawValue })")

        return steps
    }
}
