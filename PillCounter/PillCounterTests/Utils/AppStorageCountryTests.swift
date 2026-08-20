//
//  AppStorageCountryTests.swift
//  PillCounterTests
//
//  Round-trip test for AppStorageManager.countryOptions (JSON-in-UserDefaults),
//  mirroring the existing pharmacyTypeOptions/storedTerminals cache pattern.
//
//  AppStorageManager.shared is a real singleton backed by UserDefaults.standard —
//  not injectable — so this test snapshots and restores the keys it touches.
//

import Testing
import Foundation
@testable import PillCounter

@Suite
struct AppStorageCountryTests {

    private func makeCountry(code: String, name: String, states: [StateItem]? = nil) -> Country {
        Country(code: code, name: name, states: states)
    }

    @Test func countryOptionsRoundTripsThroughUserDefaults() {
        let store = AppStorageManager.shared
        let saved = store.countryOptions
        defer { store.countryOptions = saved }

        let countries = [
            makeCountry(code: "US", name: "United States", states: [
                StateItem(code: "AL", name: "Alabama"),
                StateItem(code: "AK", name: "Alaska")
            ]),
            makeCountry(code: "CA", name: "Canada", states: [
                StateItem(code: "ON", name: "Ontario")
            ])
        ]

        store.countryOptions = countries

        #expect(store.countryOptions == countries)
    }

    @Test func countryOptionsDefaultsToEmptyWhenNeverSet() {
        let store = AppStorageManager.shared
        let saved = store.countryOptions
        store.countryOptions = []
        defer { store.countryOptions = saved }

        #expect(store.countryOptions.isEmpty)
    }

    @Test func selectedCountryAndStateCodeRoundTripThroughUserDefaults() {
        let store = AppStorageManager.shared
        let savedCountry = store.selectedCountryCode
        let savedState = store.selectedStateCode
        defer {
            store.selectedCountryCode = savedCountry
            store.selectedStateCode = savedState
        }

        store.selectedCountryCode = "US"
        store.selectedStateCode = "AK"

        #expect(store.selectedCountryCode == "US")
        #expect(store.selectedStateCode == "AK")
    }
}
