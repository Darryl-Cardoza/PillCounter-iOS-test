//
//  ControlledStep.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/02/26.
//

enum ControlledStep: String, CaseIterable {
    case empty = "EMPTY"
    case parentContainer = "PARENT"
    case target = "TARGET"
    case doubleCount = "DOUBLE"
    case vialImage = "VIAL"
    case backCount = "BACK"
}


extension ControlledStep {
    var displayText: String? {
        switch self {
        case .empty:
            return nil
        case .parentContainer:
            return "Count all pills from container"
        case .target:
            return "Count Prescribed quantity"
        case .doubleCount:
            return "Recount Prescribed Quantity."
        case .backCount:
            return "Count all remaining Pills from Container"
        case .vialImage:
            return nil
        }
    }
}
