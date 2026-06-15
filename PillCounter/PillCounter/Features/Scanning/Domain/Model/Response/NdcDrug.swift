//
//  NdcDrug.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/03/26.
//
import Foundation

struct NdcDrug: Codable {
    let drugCode: String?
    let brandName: String?
    let genericName: String?
    let splittable: Bool?
    let standardName: String?
    let activeIngredients: [ActiveIngredient]?
    let isHazardous: Bool?
    let glovesRequired: Bool?
    let hazardousIngredients: [HazardousIngredient]?
    let regulatory: DrugRegulatory?
    let dosageForm: [String]?
    let lookupName: String?
    let manufacturer: String?
    let route: [String]?
    let therapeutic: DrugTherapeutic?
    let images: DrugImages?
    let package: NdcPackage?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case drugCode = "drug_code"
        case brandName = "brand_name"
        case genericName = "generic_name"
        case splittable
        case standardName = "standard_name"
        case activeIngredients = "active_ingredients"
        case isHazardous = "is_hazardous"
        case glovesRequired = "gloves_required"
        case hazardousIngredients = "hazardous_ingredients"
        case regulatory
        case dosageForm = "dosage_form"
        case lookupName = "lookup_name"
        case manufacturer
        case route
        case therapeutic
        case images
        case package
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drugCode              = try? c.decodeIfPresent(String.self, forKey: .drugCode)
        brandName             = try? c.decodeIfPresent(String.self, forKey: .brandName)
        genericName           = try? c.decodeIfPresent(String.self, forKey: .genericName)
        splittable            = try? c.decodeIfPresent(Bool.self,   forKey: .splittable)
        standardName          = try? c.decodeIfPresent(String.self, forKey: .standardName)
        activeIngredients     = try? c.decodeIfPresent([ActiveIngredient].self, forKey: .activeIngredients)
        isHazardous           = try? c.decodeIfPresent(Bool.self,   forKey: .isHazardous)
        glovesRequired        = try? c.decodeIfPresent(Bool.self,   forKey: .glovesRequired)
        hazardousIngredients  = try? c.decodeIfPresent([HazardousIngredient].self, forKey: .hazardousIngredients)
        regulatory            = try? c.decodeIfPresent(DrugRegulatory.self, forKey: .regulatory)
        lookupName            = try? c.decodeIfPresent(String.self, forKey: .lookupName)
        manufacturer          = try? c.decodeIfPresent(String.self, forKey: .manufacturer)
        therapeutic           = try? c.decodeIfPresent(DrugTherapeutic.self, forKey: .therapeutic)
        images                = try? c.decodeIfPresent(DrugImages.self, forKey: .images)
        package               = try? c.decodeIfPresent(NdcPackage.self, forKey: .package)
        updatedAt             = try? c.decodeIfPresent(String.self, forKey: .updatedAt)

        // dosage_form and route can be either [String] or a single String
        if let arr = try? c.decodeIfPresent([String].self, forKey: .dosageForm) {
            dosageForm = arr
        } else if let str = try? c.decodeIfPresent(String.self, forKey: .dosageForm) {
            dosageForm = [str]
        } else {
            dosageForm = nil
        }

        if let arr = try? c.decodeIfPresent([String].self, forKey: .route) {
            route = arr
        } else if let str = try? c.decodeIfPresent(String.self, forKey: .route) {
            route = [str]
        } else {
            route = nil
        }
    }
}

struct ActiveIngredient: Codable {
    let name: String?
    let strength: String?
    let strengthRaw: String?
    let strengthValue: String?
    let strengthUnit: String?
    let ingredientCode: String?

    enum CodingKeys: String, CodingKey {
        case name
        case strength
        case strengthRaw = "strength_raw"
        case strengthValue = "strength_value"
        case strengthUnit = "strength_unit"
        case ingredientCode = "ingredient_code"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name           = try? c.decodeIfPresent(String.self, forKey: .name)
        strength       = try? c.decodeIfPresent(String.self, forKey: .strength)
        strengthRaw    = try? c.decodeIfPresent(String.self, forKey: .strengthRaw)
        strengthValue  = try? c.decodeIfPresent(String.self, forKey: .strengthValue)
        strengthUnit   = try? c.decodeIfPresent(String.self, forKey: .strengthUnit)
        ingredientCode = try? c.decodeIfPresent(String.self, forKey: .ingredientCode)
    }
}

struct HazardousIngredient: Codable {
    let originalIngredient: String?
    let normalizedIngredient: String?
    let table: Int?

    enum CodingKeys: String, CodingKey {
        case originalIngredient = "original_ingredient"
        case normalizedIngredient = "normalized_ingredient"
        case table
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originalIngredient   = try? c.decodeIfPresent(String.self, forKey: .originalIngredient)
        normalizedIngredient = try? c.decodeIfPresent(String.self, forKey: .normalizedIngredient)
        table                = try? c.decodeIfPresent(Int.self,    forKey: .table)
    }
}

struct DrugRegulatory: Codable {
    let schedule: String?
    let isControlled: Bool?
    let status: String?
    let statusDate: String?

    enum CodingKeys: String, CodingKey {
        case schedule
        case isControlled = "is_controlled"
        case status
        case statusDate = "status_date"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedule     = try? c.decodeIfPresent(String.self, forKey: .schedule)
        isControlled = try? c.decodeIfPresent(Bool.self,   forKey: .isControlled)
        status       = try? c.decodeIfPresent(String.self, forKey: .status)
        statusDate   = try? c.decodeIfPresent(String.self, forKey: .statusDate)
    }
}

struct DrugTherapeutic: Codable {
    let primaryClass: String?
    let secondaryClasses: [String]?
    let rxclassSource: String?
    let fdaNote: String?
    let atcCodes: [String]?

    enum CodingKeys: String, CodingKey {
        case primaryClass = "primary_class"
        case secondaryClasses = "secondary_classes"
        case rxclassSource = "rxclass_source"
        case fdaNote = "fda_note"
        case atcCodes = "atc_codes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryClass     = try? c.decodeIfPresent(String.self,   forKey: .primaryClass)
        secondaryClasses = try? c.decodeIfPresent([String].self, forKey: .secondaryClasses)
        rxclassSource    = try? c.decodeIfPresent(String.self,   forKey: .rxclassSource)
        fdaNote          = try? c.decodeIfPresent(String.self,   forKey: .fdaNote)
        atcCodes         = try? c.decodeIfPresent([String].self, forKey: .atcCodes)
    }
}

struct DrugImages: Codable {
    let total: Int?
    let primary: String?
    let all: [DrugImageItem]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total   = try? c.decodeIfPresent(Int.self,             forKey: .total)
        primary = try? c.decodeIfPresent(String.self,          forKey: .primary)
        all     = try? c.decodeIfPresent([DrugImageItem].self, forKey: .all)
    }
}

struct DrugImageItem: Codable {
    let url: String?
    let filename: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url      = try? c.decodeIfPresent(String.self, forKey: .url)
        filename = try? c.decodeIfPresent(String.self, forKey: .filename)
    }
}


extension NdcDrug {

    var safeQuantity: Int32 {
        // Case 1: structured (best)
        if let qty = package?.levels?.first?.contains?.quantity {
            return Int32(qty)
        }

        // Case 2: fallback to level quantity
        if let qty = package?.levels?.first?.quantity {
            return Int32(qty)
        }

        // Case 3: fallback to description
        if let desc = package?.description {
            let numbers = desc
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }

            return Int32(numbers.first ?? 0)
        }

        return 0
    }
}
