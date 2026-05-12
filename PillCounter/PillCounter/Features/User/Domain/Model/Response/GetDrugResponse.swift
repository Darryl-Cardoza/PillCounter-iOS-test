//
//  GetDrugResponse.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

struct GetDrugResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: DrugData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct DrugData: Codable {
    let productNDC: String?
    let packageNDC: String?
    let genericName: String?
    let brandName: String?
    let activeIngredients: [ActiveIngredient]?
    let dosageForm: String?
    let packaging: [Packaging]?
    let drugClass: DrugClass?
    let therapeuticID: String?
    let specificProductID: String?
    let matchType: String?

    enum CodingKeys: String, CodingKey {
        case productNDC = "product_ndc"
        case packageNDC = "package_ndc"
        case genericName = "generic_name"
        case brandName = "brand_name"
        case activeIngredients = "active_ingredients"
        case dosageForm = "dosage_form"
        case packaging
        case drugClass = "class"
        case therapeuticID = "theraupetic_id"
        case specificProductID = "specific_product_id"
        case matchType = "_match_type"
    }
}

struct ActiveIngredient: Codable {
    let name: String?
    let strength: String?
}

struct Packaging: Codable {
    let packageNDC: String?
    let description: String?
    let marketingStartDate: String?
    let marketingEndDate: String?
    let sample: Bool?

    enum CodingKeys: String, CodingKey {
        case packageNDC = "package_ndc"
        case description
        case marketingStartDate = "marketing_start_date"
        case marketingEndDate = "marketing_end_date"
        case sample
    }
}

struct DrugClass: Codable {
    let pharmClass: [String]?
    let pharmClassMOA: [String]?
    let pharmClassPE: [String]?
    let pharmClassCS: [String]?
    let pharmClassEPC: [String]?

    enum CodingKeys: String, CodingKey {
        case pharmClass = "pharm_class"
        case pharmClassMOA = "pharm_class_moa"
        case pharmClassPE = "pharm_class_pe"
        case pharmClassCS = "pharm_class_cs"
        case pharmClassEPC = "pharm_class_epc"
    }
}

