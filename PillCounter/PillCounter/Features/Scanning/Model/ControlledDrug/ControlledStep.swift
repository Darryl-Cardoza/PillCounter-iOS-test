//
//  ControlledStep.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/02/26.
//



extension ControlledStep {

    static let orderedSteps: [ControlledStep] = [
        .containerInitiate,
        .targetVerification,
        .targetReverification,
        .vial,
        .containerPending
    ]

    func nextStep(in steps: [ControlledStep]) -> ControlledStep {
        guard let index = steps.firstIndex(of: self),
              index + 1 < steps.count
        else { return self }
        return steps[index + 1]
    }
}



// MARK: - ASSET NAME MAPPING
// Replace each value with your exact Asset Catalog image name.
 extension ControlledStepRow {

    func assetName(for step: ControlledStep) -> String {
 
        switch step {
            
        case .scan:
            return "scan_step1"
            
        case .containerInitiate:
            return "parent_count_step2"
            
        case .targetVerification:
            return "target_count_step3"
            
        case .targetReverification:
            return "double_count_step4"
            
        case .vial:
            return "vial_step5"
            
        case .containerPending:
            return "parent_count_step2"
        }
    }
}
