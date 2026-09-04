//
//  NdcComparisonResponse.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/03/26.
//

import Foundation

struct NdcComparisonResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: NdcComparisonData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status    = try? c.decodeIfPresent(Int.self,              forKey: .status)
        isSuccess = try? c.decodeIfPresent(Bool.self,             forKey: .isSuccess)
        message   = try? c.decodeIfPresent(String.self,           forKey: .message)
        token     = try? c.decodeIfPresent(String.self,           forKey: .token)
        data      = try? c.decodeIfPresent(NdcComparisonData.self, forKey: .data)
    }
}

struct NdcComparisonData: Codable {
    let isNdcSame: Bool?
    let isNdcEquivalent: Bool?
    let targetNdc: NdcDrug?
    let scannedNdc: NdcDrug?

    enum CodingKeys: String, CodingKey {
        case isNdcSame = "is_ndc_same"
        case isNdcEquivalent = "is_ndc_equivalent"
        case targetNdc = "target_ndc"
        case scannedNdc = "scanned_ndc"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isNdcSame      = try? c.decodeIfPresent(Bool.self,    forKey: .isNdcSame)
        isNdcEquivalent = try? c.decodeIfPresent(Bool.self,   forKey: .isNdcEquivalent)
        targetNdc      = try? c.decodeIfPresent(NdcDrug.self, forKey: .targetNdc)
        scannedNdc     = try? c.decodeIfPresent(NdcDrug.self, forKey: .scannedNdc)
    }
}

struct NdcPackage: Codable {
    let description: String?
    let sizes: [String]?
    let levels: [PackageLevel]?
    let stockQty: Int?

    enum CodingKeys: String, CodingKey {
        case description
        case sizes
        case levels
        case stockQty = "stock_qty"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = try? c.decodeIfPresent(String.self,         forKey: .description)
        sizes       = try? c.decodeIfPresent([String].self,       forKey: .sizes)
        levels      = try? c.decodeIfPresent([PackageLevel].self, forKey: .levels)
        stockQty    = try? c.decodeIfPresent(Int.self,             forKey: .stockQty)
    }
}

struct PackageLevel: Codable {
    let type: String?
    let name: String?
    let quantity: Int?
    let modifiers: String?
    let material: String?
    let contains: PackageContains?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type      = try? c.decodeIfPresent(String.self,          forKey: .type)
        name      = try? c.decodeIfPresent(String.self,          forKey: .name)
        quantity  = try? c.decodeIfPresent(Int.self,             forKey: .quantity)
        modifiers = try? c.decodeIfPresent(String.self,          forKey: .modifiers)
        material  = try? c.decodeIfPresent(String.self,          forKey: .material)
        contains  = try? c.decodeIfPresent(PackageContains.self, forKey: .contains)
    }
}

final class PackageContains: Codable {
    let type: String?
    let name: String?
    let quantity: Int?
    let modifiers: [String]?
    let material: String?
    let contains: PackageContains?

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type      = try? c.decodeIfPresent(String.self,           forKey: .type)
        name      = try? c.decodeIfPresent(String.self,           forKey: .name)
        quantity  = try? c.decodeIfPresent(Int.self,              forKey: .quantity)
        modifiers = try? c.decodeIfPresent([String].self,         forKey: .modifiers)
        material  = try? c.decodeIfPresent(String.self,           forKey: .material)
        contains  = try? c.decodeIfPresent(PackageContains.self,  forKey: .contains)
    }
}
