//
//  UserViewModelCountryStateTests.swift
//  PillCounterTests
//
//  Tests for the Country/State fetch/cache flow on UserViewModel: fetchCountries()
//  populates countryOptions and overwrites the cache on every successful call,
//  falls back to cache on failure. Country -> state filtering itself lives in the
//  View (selectedCountry?.states), so it's exercised via the Country model directly.
//

import Testing
import Foundation
@testable import PillCounter

@MainActor
@Suite
struct UserViewModelCountryStateTests {

    // MARK: - Fixtures

    private func makeViewModel(userRepo: MockTerminalUserRepository) -> UserViewModel {
        UserViewModel(userLocalDB: MockUserDataSource(), userRepo: userRepo)
    }

    private func countryResponse(_ countries: [Country]?, isSuccess: Bool = true) -> CountryResponse {
        CountryResponse(status: 200, isSuccess: isSuccess, message: nil, token: nil, data: CountryData(countries: countries))
    }

    private let usa = Country(code: "US", name: "United States", states: [
        StateItem(code: "AL", name: "Alabama"),
        StateItem(code: "AK", name: "Alaska")
    ])
    private let canada = Country(code: "CA", name: "Canada", states: [
        StateItem(code: "ON", name: "Ontario")
    ])

    // MARK: - Storage snapshot/restore

    private func withCleanCountryStorage(_ body: () async throws -> Void) async rethrows {
        let store = AppStorageManager.shared
        let savedOptions = store.countryOptions
        let savedCountry = store.selectedCountryCode
        let savedState = store.selectedStateCode

        store.countryOptions = []
        store.selectedCountryCode = nil
        store.selectedStateCode = nil

        defer {
            store.countryOptions = savedOptions
            store.selectedCountryCode = savedCountry
            store.selectedStateCode = savedState
        }

        try await body()
    }

    // MARK: - fetchCountries: success overwrites cache

    @Test func fetchCountriesPopulatesOptionsAndOverwritesCache() async throws {
        try await withCleanCountryStorage {
            let repo = MockTerminalUserRepository()
            repo.getCountriesResult = .success(countryResponse([usa, canada]))
            let vm = makeViewModel(userRepo: repo)

            await vm.fetchCountries()

            #expect(vm.countryOptions == [usa, canada])
            #expect(AppStorageManager.shared.countryOptions == [usa, canada])
        }
    }

    // MARK: - fetchCountries: called every time, overwrites stale cache

    @Test func fetchCountriesOverwritesPreviouslyCachedList() async throws {
        try await withCleanCountryStorage {
            AppStorageManager.shared.countryOptions = [canada]
            let repo = MockTerminalUserRepository()
            repo.getCountriesResult = .success(countryResponse([usa]))
            let vm = makeViewModel(userRepo: repo)

            await vm.fetchCountries()

            #expect(vm.countryOptions == [usa])
            #expect(AppStorageManager.shared.countryOptions == [usa])
        }
    }

    // MARK: - fetchCountries: network failure falls back to cache

    @Test func fetchCountriesFallsBackToCacheOnNetworkFailure() async throws {
        try await withCleanCountryStorage {
            AppStorageManager.shared.countryOptions = [usa]
            let repo = MockTerminalUserRepository()
            repo.getCountriesResult = .failure(MockRepositoryError.generic)
            let vm = makeViewModel(userRepo: repo)

            await vm.fetchCountries()

            #expect(vm.countryOptions == [usa])
        }
    }

    // MARK: - fetchCountries: unsuccessful response falls back to cache

    @Test func fetchCountriesFallsBackToCacheWhenResponseUnsuccessful() async throws {
        try await withCleanCountryStorage {
            AppStorageManager.shared.countryOptions = [canada]
            let repo = MockTerminalUserRepository()
            repo.getCountriesResult = .success(countryResponse([usa], isSuccess: false))
            let vm = makeViewModel(userRepo: repo)

            await vm.fetchCountries()

            #expect(vm.countryOptions == [canada])
        }
    }

    // MARK: - State filtering derives from the selected country's nested list

    @Test func statesForSelectedCountryMatchNestedList() {
        #expect(usa.states == [StateItem(code: "AL", name: "Alabama"), StateItem(code: "AK", name: "Alaska")])
        #expect(canada.states == [StateItem(code: "ON", name: "Ontario")])
    }

    // MARK: - hasProfileChanged: country/state changes are detected

    @Test func hasProfileChangedDetectsCountryChange() async throws {
        try await withCleanCountryStorage {
            AppStorageManager.shared.selectedCountryCode = "CA"
            AppStorageManager.shared.selectedStateCode = "ON"
            let repo = MockTerminalUserRepository()
            let vm = makeViewModel(userRepo: repo)
            vm.userProfileDetails = UserProfile(
                fname: "A", lname: "B", email: "e@x.com", phoneNumber: "1111111111",
                avatarURL: nil, isProfileCompleted: true, pharmacyName: "Pharm",
                pharmacyType: "chain", npiID: "111", isVerified: true, isPmsIntegrated: false,
                bucket: nil, role: nil, userId: "u1"
            )
            vm.firstName = "A"
            vm.lastName = "B"
            vm.pharmacyName = "Pharm"
            vm.phoneNumber = "1111111111"
            vm.npiID = "111"

            let changed = vm.hasProfileChanged(pharmacyTypeCode: "chain", countryCode: "US", stateCode: "AL")

            #expect(changed == true)
        }
    }

    @Test func hasProfileChangedFalseWhenCountryStateUnchanged() async throws {
        try await withCleanCountryStorage {
            AppStorageManager.shared.selectedCountryCode = "US"
            AppStorageManager.shared.selectedStateCode = "AK"
            let repo = MockTerminalUserRepository()
            let vm = makeViewModel(userRepo: repo)
            vm.userProfileDetails = UserProfile(
                fname: "A", lname: "B", email: "e@x.com", phoneNumber: "1111111111",
                avatarURL: nil, isProfileCompleted: true, pharmacyName: "Pharm",
                pharmacyType: "chain", npiID: "111", isVerified: true, isPmsIntegrated: false,
                bucket: nil, role: nil, userId: "u1"
            )
            vm.firstName = "A"
            vm.lastName = "B"
            vm.pharmacyName = "Pharm"
            vm.phoneNumber = "1111111111"
            vm.npiID = "111"

            let changed = vm.hasProfileChanged(pharmacyTypeCode: "chain", countryCode: "US", stateCode: "AK")

            #expect(changed == false)
        }
    }

    // MARK: - updateUserProfile: sends country/state codes when changed

    @Test func updateUserProfileSendsCountryAndStateWhenChanged() async throws {
        try await withCleanCountryStorage {
            AppStorageManager.shared.selectedCountryCode = "CA"
            AppStorageManager.shared.selectedStateCode = "ON"
            let repo = MockTerminalUserRepository()
            repo.updateUserProfileResult = .success(
                UserResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil)
            )
            let vm = UserViewModel(userLocalDB: MockUserDataSource(), userRepo: repo)
            vm.userProfileDetails = UserProfile(
                fname: "A", lname: "B", email: "e@x.com", phoneNumber: "1111111111",
                avatarURL: nil, isProfileCompleted: true, pharmacyName: "Pharm",
                pharmacyType: "chain", npiID: "111", isVerified: true, isPmsIntegrated: false,
                bucket: nil, role: nil, userId: "u1"
            )
            vm.firstName = "A"
            vm.lastName = "B"
            vm.pharmacyName = "Pharm"
            vm.phoneNumber = "1111111111"
            vm.npiID = "111"

            await vm.updateUserProfile(pharmacyTypeCode: "chain", countryCode: "US", stateCode: "AL")

            let sent = repo.lastUpdateUserProfileRequest
            #expect(sent?.country == "US")
            #expect(sent?.state == "AL")
            #expect(AppStorageManager.shared.selectedCountryCode == "US")
            #expect(AppStorageManager.shared.selectedStateCode == "AL")
        }
    }
}
