//
//  NdcValidationRequest.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/03/26.
//

import Foundation

struct NdcValidationRequest: Codable {
    let targetNdc: String
    let scannedNdc: String
    
    enum CodingKeys: String, CodingKey {
        case targetNdc = "target_ndc"
        case scannedNdc = "scanned_ndc"
    }
}
