//
//  NdcComparisonResponse.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/03/26.
//
//
//  NdcComparisonResponse.swift
//

import Foundation

struct NdcComparisonResponse: Codable {
    let status: Int
    let isSuccess: Bool
    let message: String
    let token: String?
    let data: NdcComparisonData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct NdcComparisonData: Codable {
    let isNdcSame: Bool
    let isNdcEquivalent: Bool
    let targetNdc: NdcDrug?
    let scannedNdc: NdcDrug?

    enum CodingKeys: String, CodingKey {
        case isNdcSame = "is_ndc_same"
        case isNdcEquivalent = "is_ndc_equivalent"
        case targetNdc = "target_ndc"
        case scannedNdc = "scanned_ndc"
    }
}


struct ActiveIngredients: Codable {
    let name: String
    let strength: String
}


struct TherapeuticRxClass: Codable {
    let primaryClass: String?
    let secondaryClasses: [String]?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case primaryClass = "primary_class"
        case secondaryClasses = "secondary_classes"
        case source
    }
}

struct TherapeuticFDA: Codable {
    let note: String?
}

struct DrugImage: Codable {
    let link: String?
}


struct NdcPackage: Codable {
    let ndc: String?
    let description: String?
    let levels: [PackageLevel]? 
}

struct PackageLevel: Codable {
    let type: String?
    let name: String?
    let quantity: Int?
    let modifiers: String?
    let material: String?
    let contains: PackageContains?
}

struct PackageContains: Codable{
    let type: String?
    let name: String?
    let quantity: Int?
    let modifiers: [String]?
    let material: String?
}
