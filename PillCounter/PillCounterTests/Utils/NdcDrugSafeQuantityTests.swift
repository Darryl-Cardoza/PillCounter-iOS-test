//
//  NdcDrugSafeQuantityTests.swift
//  PillCounterTests
//
//  Regression coverage for NdcDrug.safeQuantity's fallback chain — specifically the
//  missing package.stock_qty case that caused a scanned drug with no `levels`
//  breakdown (but a real stock_qty from the backend, e.g. 1000) to resolve to a
//  package quantity of 0/1 instead of the real value.
//

import Foundation
import Testing
@testable import PillCounter

@Suite
struct NdcDrugSafeQuantityTests {

    private func decodeDrug(packageJson: String) throws -> NdcDrug {
        let json = """
        {
          "drug_code": "00000-0000-00",
          "package": \(packageJson)
        }
        """
        return try JSONDecoder().decode(NdcDrug.self, from: Data(json.utf8))
    }

    @Test func safeQuantityUsesStructuredContainsQuantityWhenPresent() throws {
        let drug = try decodeDrug(packageJson: """
        { "levels": [ { "quantity": 30, "contains": { "quantity": 1000 } } ] }
        """)
        #expect(drug.safeQuantity == 1000)
    }

    @Test func safeQuantityFallsBackToLevelQuantityWhenNoContains() throws {
        let drug = try decodeDrug(packageJson: """
        { "levels": [ { "quantity": 500 } ] }
        """)
        #expect(drug.safeQuantity == 500)
    }

    /// The reported bug: no `levels` array at all, but the package carries its own
    /// stock_qty — previously fell straight through to the description-parsing case
    /// (and then to 0 if the description also had no leading number), showing 1
    /// bottle / 1 pill in the UI instead of the real 1000.
    @Test func safeQuantityFallsBackToPackageStockQtyWhenNoLevels() throws {
        let drug = try decodeDrug(packageJson: """
        { "description": "Bottle", "stock_qty": 1000 }
        """)
        #expect(drug.safeQuantity == 1000)
    }

    @Test func safeQuantityParsesLeadingNumberFromDescriptionWhenNoLevelsOrStockQty() throws {
        let drug = try decodeDrug(packageJson: """
        { "description": "bottle, 250 each" }
        """)
        #expect(drug.safeQuantity == 250)
    }

    @Test func safeQuantityStripsThousandsSeparatorFromDescriptionNumber() throws {
        let drug = try decodeDrug(packageJson: """
        { "description": "bottle, 1,000 each" }
        """)
        #expect(drug.safeQuantity == 1000)
    }

    @Test func safeQuantityReturnsZeroWhenNothingUsable() throws {
        let drug = try decodeDrug(packageJson: """
        { "description": "no numbers here" }
        """)
        #expect(drug.safeQuantity == 0)
    }
}
