//
//  PillDetector.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import CoreML
import UIKit
import Vision

final class PillDetector {

    // singleton
    static let shared = PillDetector()

    // model
    private(set) var model: best?

    private init() {
        loadModel()
    }

    // load model
    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            
            config.computeUnits = .cpuOnly
            
            let mlModel = try best(configuration: config)
            self.model = mlModel

        } catch let error {
            print("❌ FALIED TO LOAD MODEL: \(error)")
        }
    }
}
