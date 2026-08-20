//
//  UserViewModelTerminalTests.swift
//  PillCounterTests
//
//  Tests for the terminal claim/release flow on UserViewModel: updateTerminal(),
//  loadTerminals(), hydrateTerminalsFromCache(). UserViewModel is @MainActor.
//
//  AppStorageManager.shared is a real singleton backed by UserDefaults.standard —
//  not injectable — so every test snapshots and restores the terminal-related keys
//  it touches to avoid leaking state across tests or polluting the real device store.
//

import Testing
import Foundation
@testable import PillCounter

@MainActor
@Suite
struct UserViewModelTerminalTests {

    // MARK: - Fixtures

    private func makeTerminal(id: String, name: String, isActive: Bool = true, deviceKey: String? = nil) -> UserTerminal {
        UserTerminal(
            terminalId: id,
            terminalName: name,
            isActive: isActive,
            deviceKey: deviceKey,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func makeViewModel(userRepo: MockTerminalUserRepository) -> UserViewModel {
        UserViewModel(
            userLocalDB: MockUserDataSource(),
            userRepo: userRepo
        )
    }

    private func terminalListResponse(_ terminals: [UserTerminal]?, isSuccess: Bool = true) -> TerminalListResponse {
        TerminalListResponse(status: 200, isSuccess: isSuccess, message: nil, data: TerminalListData(terminals: terminals))
    }

    private func updateTerminalResponse(isSuccess: Bool) -> UpdateTerminalResponse {
        UpdateTerminalResponse(status: isSuccess ? 200 : 500, isSuccess: isSuccess, message: nil)
    }

    // MARK: - Storage snapshot/restore

    /// Runs `body` with a clean terminal-cache + deviceKey slate, then restores
    /// whatever was there before — so this suite never leaks into other tests or
    /// the real device's UserDefaults.
    private func withCleanTerminalStorage(deviceKey: String = "device-under-test", _ body: () async throws -> Void) async rethrows {
        let store = AppStorageManager.shared
        let savedTerminals = store.storedTerminals
        let savedSelectedName = store.selectedTerminalName
        let savedDeviceKey = store.deviceKey

        store.clearTerminalCache()
        store.deviceKey = deviceKey

        defer {
            store.clearTerminalCache()
            store.storedTerminals = savedTerminals
            store.selectedTerminalName = savedSelectedName
            store.deviceKey = savedDeviceKey
        }

        try await body()
    }

    // MARK: - updateTerminal: pre-claim re-fetch failure

    @Test func updateTerminalAbortsWhenPreClaimRefetchFails() async throws {
        try await withCleanTerminalStorage { [self] in
            let repo = MockTerminalUserRepository()
            repo.getTerminalsResults = [.failure(MockRepositoryError.generic)]
            let vm = makeViewModel(userRepo: repo)
            vm.terminals = [makeTerminal(id: "1", name: "Bay 1")]

            let result = await vm.updateTerminal(makeTerminal(id: "2", name: "Bay 2"))

            #expect(result == false)
            #expect(vm.terminalErrorMessage != nil)
            // Must not fall through to the update-terminal call on stale data.
            #expect(repo.updateTerminalCallCount == 0)
            // Stale in-memory list must not be trusted/mutated into a false claim.
            #expect(vm.selectedTerminal?.terminalId != "2")
        }
    }

    // MARK: - updateTerminal: already holds target terminal

    @Test func updateTerminalNoOpsWhenAlreadyHoldingTarget() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            let target = makeTerminal(id: "1", name: "Bay 1", deviceKey: "device-A")
            repo.getTerminalsResults = [.success(terminalListResponse([target]))]
            let vm = makeViewModel(userRepo: repo)

            let result = await vm.updateTerminal(target)

            #expect(result == true)
            #expect(vm.selectedTerminal?.terminalId == "1")
            // Already-held path must not call the claim endpoint.
            #expect(repo.updateTerminalCallCount == 0)
        }
    }

    // MARK: - updateTerminal: successful claim

    @Test func updateTerminalClaimsAndRefetchesLiveListOnSuccess() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            let target = makeTerminal(id: "2", name: "Bay 2")
            // Pre-claim fetch: device holds nothing yet.
            repo.getTerminalsResults = [
                .success(terminalListResponse([makeTerminal(id: "1", name: "Bay 1"), target])),
                // Post-claim fetch: server now shows device-A holding Bay 2.
                .success(terminalListResponse([
                    makeTerminal(id: "1", name: "Bay 1"),
                    makeTerminal(id: "2", name: "Bay 2", deviceKey: "device-A")
                ]))
            ]
            repo.updateTerminalResults = [.success(updateTerminalResponse(isSuccess: true))]
            let vm = makeViewModel(userRepo: repo)

            let result = await vm.updateTerminal(target)

            #expect(result == true)
            #expect(repo.updateTerminalCallCount == 1)
            #expect(repo.getTerminalsCallCount == 2)
            #expect(vm.selectedTerminal?.terminalId == "2")
            #expect(vm.terminals.first(where: { $0.terminalId == "2" })?.deviceKey == "device-A")
            #expect(vm.terminalErrorMessage == nil)
        }
    }

    // MARK: - updateTerminal: post-claim re-fetch failure

    @Test func updateTerminalStillReturnsSuccessWhenPostClaimRefetchFails() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            let target = makeTerminal(id: "2", name: "Bay 2")
            repo.getTerminalsResults = [
                .success(terminalListResponse([makeTerminal(id: "1", name: "Bay 1"), target])),
                .failure(MockRepositoryError.generic)
            ]
            repo.updateTerminalResults = [.success(updateTerminalResponse(isSuccess: true))]
            let vm = makeViewModel(userRepo: repo)

            let result = await vm.updateTerminal(target)

            // Claim itself succeeded server-side — the failed re-fetch afterward
            // shouldn't flip this back to failure, just leaves terminals stale
            // until next loadTerminals().
            #expect(result == true)
            #expect(vm.selectedTerminal?.terminalId == "2")
        }
    }

    // MARK: - updateTerminal: 409 conflict

    @Test func updateTerminalSurfacesConflictMessageOn409() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            let target = makeTerminal(id: "2", name: "Bay 2")
            repo.getTerminalsResults = [.success(terminalListResponse([makeTerminal(id: "1", name: "Bay 1"), target]))]
            repo.updateTerminalResults = [.failure(APIError.conflict)]
            let vm = makeViewModel(userRepo: repo)

            let result = await vm.updateTerminal(target)

            #expect(result == false)
            #expect(vm.terminalErrorMessage == L10n.Profile.Error.errorTerminalAlreadyClaimedMessage)
        }
    }

    // MARK: - updateTerminal: generic claim failure

    @Test func updateTerminalReturnsFalseWithoutConflictMessageOnGenericFailure() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            let target = makeTerminal(id: "2", name: "Bay 2")
            repo.getTerminalsResults = [.success(terminalListResponse([makeTerminal(id: "1", name: "Bay 1"), target]))]
            repo.updateTerminalResults = [.failure(MockRepositoryError.generic)]
            let vm = makeViewModel(userRepo: repo)

            let result = await vm.updateTerminal(target)

            #expect(result == false)
            #expect(vm.terminalErrorMessage != L10n.Profile.Error.errorTerminalAlreadyClaimedMessage)
        }
    }

    // MARK: - updateTerminal: missing id/name

    @Test func updateTerminalReturnsFalseWhenTerminalMissingIdOrName() async throws {
        try await withCleanTerminalStorage { [self] in
            let repo = MockTerminalUserRepository()
            let vm = makeViewModel(userRepo: repo)
            let malformed = makeTerminal(id: "", name: "Bay 1")
            let noId = UserTerminal(terminalId: nil, terminalName: "Bay 1", isActive: true, deviceKey: nil, createdAt: nil, updatedAt: nil)

            let result1 = await vm.updateTerminal(noId)
            let result2 = await vm.updateTerminal(malformed)

            #expect(result1 == false)
            #expect(result2 == false)
            // Guards before any network call.
            #expect(repo.getTerminalsCallCount == 0)
        }
    }

    // MARK: - loadTerminals: happy path, device holds a terminal

    @Test func loadTerminalsSelectsTerminalHeldByThisDevice() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            repo.getTerminalsResults = [.success(terminalListResponse([
                makeTerminal(id: "1", name: "Bay 1", deviceKey: "device-A"),
                makeTerminal(id: "2", name: "Bay 2", deviceKey: "device-B")
            ]))]
            let vm = makeViewModel(userRepo: repo)

            await vm.loadTerminals()

            #expect(vm.selectedTerminal?.terminalId == "1")
            #expect(vm.pendingTerminal?.terminalId == "1")
            #expect(vm.terminals.count == 2)
        }
    }

    // MARK: - loadTerminals: server confirms device holds nothing -> clears stale selection

    @Test func loadTerminalsClearsStaleSelectionWhenDeviceHoldsNothing() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            repo.getTerminalsResults = [.success(terminalListResponse([
                makeTerminal(id: "1", name: "Bay 1", deviceKey: "device-B")
            ]))]
            let vm = makeViewModel(userRepo: repo)
            // Simulate a stale selection left over from a previous claim this
            // device no longer holds (e.g. released elsewhere, no 409 ever seen).
            vm.selectedTerminal = makeTerminal(id: "1", name: "Bay 1", deviceKey: "device-A")
            vm.pendingTerminal = vm.selectedTerminal

            await vm.loadTerminals()

            #expect(vm.selectedTerminal == nil)
            #expect(vm.pendingTerminal == nil)
        }
    }

    // MARK: - loadTerminals: empty server list falls back to cache

    @Test func loadTerminalsFallsBackToCacheWhenServerListEmpty() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            repo.getTerminalsResults = [.success(terminalListResponse([]))]
            AppStorageManager.shared.storedTerminals = [makeTerminal(id: "9", name: "Cached Bay", deviceKey: "device-A")]
            let vm = makeViewModel(userRepo: repo)

            await vm.loadTerminals()

            #expect(vm.terminals.first?.terminalId == "9")
            #expect(vm.selectedTerminal?.terminalId == "9")
        }
    }

    // MARK: - loadTerminals: network failure falls back to cache

    @Test func loadTerminalsFallsBackToCacheOnNetworkFailure() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            repo.getTerminalsResults = [.failure(MockRepositoryError.generic)]
            AppStorageManager.shared.storedTerminals = [makeTerminal(id: "9", name: "Cached Bay", deviceKey: "device-A")]
            let vm = makeViewModel(userRepo: repo)

            await vm.loadTerminals()

            #expect(vm.terminals.first?.terminalId == "9")
            #expect(vm.selectedTerminal?.terminalId == "9")
        }
    }

    // MARK: - hydrateTerminalsFromCache: deviceKey match takes priority over name match

    @Test func hydrateTerminalsFromCachePrefersDeviceKeyOverStoredName() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            AppStorageManager.shared.storedTerminals = [
                makeTerminal(id: "1", name: "Bay 1", deviceKey: "device-B"),
                makeTerminal(id: "2", name: "Bay 2", deviceKey: "device-A")
            ]
            // Stale persisted name points at Bay 1, but device_key ownership (Bay 2) wins.
            AppStorageManager.shared.selectedTerminalName = "Bay 1"
            let vm = makeViewModel(userRepo: repo)

            vm.hydrateTerminalsFromCache()

            #expect(vm.selectedTerminal?.terminalId == "2")
        }
    }

    // MARK: - hydrateTerminalsFromCache: no cache is a no-op

    @Test func hydrateTerminalsFromCacheNoOpsWhenCacheEmpty() async throws {
        try await withCleanTerminalStorage { [self] in
            let repo = MockTerminalUserRepository()
            let vm = makeViewModel(userRepo: repo)

            vm.hydrateTerminalsFromCache()

            #expect(vm.terminals.isEmpty)
            #expect(vm.selectedTerminal == nil)
        }
    }

    // MARK: - hydrateTerminalsFromCache: doesn't clobber an existing selection

    @Test func hydrateTerminalsFromCacheDoesNotOverwriteExistingSelection() async throws {
        try await withCleanTerminalStorage(deviceKey: "device-A") { [self] in
            let repo = MockTerminalUserRepository()
            AppStorageManager.shared.storedTerminals = [makeTerminal(id: "1", name: "Bay 1", deviceKey: "device-A")]
            let vm = makeViewModel(userRepo: repo)
            let alreadySelected = makeTerminal(id: "5", name: "Bay 5")
            vm.selectedTerminal = alreadySelected
            vm.pendingTerminal = alreadySelected

            vm.hydrateTerminalsFromCache()

            #expect(vm.selectedTerminal?.terminalId == "5")
        }
    }

    // MARK: - loadTerminals: brand-new device/user holds nothing, must pick manually

    @Test func loadTerminalsLeavesNoSelectionForNewDeviceWithNoClaim() async throws {
        try await withCleanTerminalStorage(deviceKey: "brand-new-device") { [self] in
            let repo = MockTerminalUserRepository()
            // Server has terminals, none held by this never-before-seen device.
            repo.getTerminalsResults = [.success(terminalListResponse([
                makeTerminal(id: "1", name: "Bay 1", deviceKey: "device-A"),
                makeTerminal(id: "2", name: "Bay 2", deviceKey: "device-B")
            ]))]
            let vm = makeViewModel(userRepo: repo)

            await vm.loadTerminals()

            #expect(vm.terminals.count == 2)
            #expect(vm.selectedTerminal == nil)
            #expect(vm.pendingTerminal == nil)
        }
    }

    // MARK: - DeviceKeyProvider: stable across repeated reads (same install)

    @Test func deviceKeyProviderReturnsSameKeyAcrossRepeatedCalls() async throws {
        let store = AppStorageManager.shared
        let saved = store.deviceKey
        store.deviceKey = nil
        defer { store.deviceKey = saved }

        let first = DeviceKeyProvider.shared.getDeviceKey()
        let second = DeviceKeyProvider.shared.getDeviceKey()
        let third = DeviceKeyProvider.shared.getDeviceKey()

        #expect(first == second)
        #expect(second == third)
        #expect(!first.isEmpty)
    }

    // MARK: - DeviceKeyProvider: reuses whatever is already cached, never regenerates

    @Test func deviceKeyProviderReusesExistingCachedValue() async throws {
        let store = AppStorageManager.shared
        let saved = store.deviceKey
        store.deviceKey = "pre-existing-cached-key"
        defer { store.deviceKey = saved }

        let key = DeviceKeyProvider.shared.getDeviceKey()

        #expect(key == "pre-existing-cached-key")
    }

    // MARK: - updateUserProfile: partial diff — only changed fields sent

    @Test func updateUserProfileSendsOnlyChangedFieldsAsPartialDiff() async throws {
        let repo = MockTerminalUserRepository()
        repo.updateUserProfileResult = .success(
            UserResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil)
        )
        let vm = UserViewModel(userLocalDB: MockUserDataSource(), userRepo: repo)

        vm.userProfileDetails = UserProfile(
            fname: "Original", lname: "Name", email: "e@x.com", phoneNumber: "1111111111",
            avatarURL: nil, isProfileCompleted: true, pharmacyName: "Pharm A",
            pharmacyType: "chain", npiID: "111", isVerified: true, isPmsIntegrated: false,
            bucket: nil, role: nil, userId: "u1"
        )
        vm.firstName = "Original"
        vm.lastName = "Name"
        vm.pharmacyName = "Pharm A"
        // Only phoneNumber actually changes.
        vm.phoneNumber = "2222222222"
        vm.npiID = "111"

        await vm.updateUserProfile(pharmacyTypeCode: "chain")

        let sent = repo.lastUpdateUserProfileRequest
        #expect(sent?.fname == nil)
        #expect(sent?.lname == nil)
        #expect(sent?.pharmacyName == nil)
        #expect(sent?.npiID == nil)
        #expect(sent?.pharmacyType == nil)
        #expect(sent?.phoneNumber == "2222222222")
    }

    // MARK: - updateUserProfile: non-UI placeholder fields never sent

    @Test func updateUserProfileNeverSendsUnusedPlaceholderFields() async throws {
        let repo = MockTerminalUserRepository()
        repo.updateUserProfileResult = .success(
            UserResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil)
        )
        let vm = UserViewModel(userLocalDB: MockUserDataSource(), userRepo: repo)
        vm.userProfileDetails = nil
        vm.firstName = "A"
        vm.lastName = "B"

        await vm.updateUserProfile(pharmacyTypeCode: nil)

        let sent = repo.lastUpdateUserProfileRequest
        // These have no UI — must stay nil/omitted, never overwritten with placeholders.
        #expect(sent?.avatarURL == nil)
        #expect(sent?.notificationsEnabled == nil)
        #expect(sent?.language == nil)
        #expect(sent?.timezone == nil)
        // Deliberate exception: always sent true to mark the profile complete.
        #expect(sent?.isProfileComplete == true)
    }

    // MARK: - updateUserProfile: no-op when nothing changed

    @Test func updateUserProfileSkipsNetworkCallWhenNothingChanged() async throws {
        let repo = MockTerminalUserRepository()
        let vm = UserViewModel(userLocalDB: MockUserDataSource(), userRepo: repo)
        let original = UserProfile(
            fname: "Same", lname: "Name", email: "e@x.com", phoneNumber: "1111111111",
            avatarURL: nil, isProfileCompleted: true, pharmacyName: "Pharm A",
            pharmacyType: "chain", npiID: "111", isVerified: true, isPmsIntegrated: false,
            bucket: nil, role: nil, userId: "u1"
        )
        vm.userProfileDetails = original
        vm.firstName = "Same"
        vm.lastName = "Name"
        vm.pharmacyName = "Pharm A"
        vm.phoneNumber = "1111111111"
        vm.npiID = "111"

        await vm.updateUserProfile(pharmacyTypeCode: "chain")

        // No result scripted on the mock — if a network call were made, the mock's
        // fatalError would have fired. Reaching here confirms hasUserProfileChanged
        // correctly short-circuited before any repo call.
        #expect(repo.lastUpdateUserProfileRequest == nil)
    }
}
