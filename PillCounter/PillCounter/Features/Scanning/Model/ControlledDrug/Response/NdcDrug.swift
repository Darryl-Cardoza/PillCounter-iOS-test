//
//  NdcDrug.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/03/26.
//

struct NdcDrug: Codable {
    let packageNdc: String
    let productNdc: String
    let splittable: Bool
    let standardName: String
    let activeIngredients: [ActiveIngredients]
    let deaSchedule: String?
    let dosageForm: String?
    let lookupName: String?
    let manufacturer: String?
    let route: [String]?
    let therapeuticRxclass: TherapeuticRxClass?
    let therapeuticFda: TherapeuticFDA?
    let image: DrugImage?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case packageNdc = "package_ndc"
        case productNdc = "product_ndc"
        case splittable
        case standardName = "standard_name"
        case activeIngredients = "active_ingredients"
        case deaSchedule = "dea_schedule"
        case dosageForm = "dosage_form"
        case lookupName = "lookup_name"
        case manufacturer
        case route
        case therapeuticRxclass = "therapeutic_rxclass"
        case therapeuticFda = "therapeutic_fda"
        case image
        case updatedAt = "updated_at"
    }
}
