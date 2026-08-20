//
//  KekDekManagerTests.swift
//  PillCounterTests
//
//  Exercises the AES-GCM wrap/unwrap primitive against the real Keychain,
//  using per-test unique aliases so runs never collide and everything is
//  torn down afterward. Serialized since they share the one Keychain.
//

import Testing
import Foundation
@testable import PillCounter

@Suite(.serialized)
struct KekDekManagerTests {

    private func uniqueAlias(_ label: String) -> String {
        "test.kekdek.\(label).\(UUID().uuidString)"
    }

    @Test func wrapThenUnwrapReturnsOriginalPlaintext() throws {
        let alias = uniqueAlias("roundtrip")
        defer { KekDekManager.shared.deleteKey(alias: alias) }

        let plaintext = Data("hello dek".utf8)
        let wrapped = try KekDekManager.shared.wrap(alias: alias, plaintext: plaintext)
        let unwrapped = try KekDekManager.shared.unwrap(alias: alias, wrapped: wrapped)

        #expect(unwrapped == plaintext)
    }

    @Test func wrappedFormatIsIvPlusCiphertextPlusTag() throws {
        let alias = uniqueAlias("format")
        defer { KekDekManager.shared.deleteKey(alias: alias) }

        let plaintext = Data(repeating: 0xAB, count: 32)
        let wrapped = try KekDekManager.shared.wrap(alias: alias, plaintext: plaintext)

        // 12-byte IV + plaintext length + 16-byte GCM tag
        #expect(wrapped.count == 12 + plaintext.count + 16)
    }

    @Test func unwrapWithMissingAliasThrowsKeyNotFound() {
        let alias = uniqueAlias("missing")
        let bogus = Data(repeating: 0, count: 12 + 16)

        #expect(throws: KekDekError.keyNotFound) {
            try KekDekManager.shared.unwrap(alias: alias, wrapped: bogus)
        }
    }

    @Test func unwrapNeverCreatesAMissingKey() {
        let alias = uniqueAlias("no-autocreate")
        let bogus = Data(repeating: 0, count: 12 + 16)

        _ = try? KekDekManager.shared.unwrap(alias: alias, wrapped: bogus)

        #expect(!KekDekManager.shared.keyExists(alias: alias))
    }

    @Test func unwrapWithWrongKeyFails() throws {
        let aliasA = uniqueAlias("wrongkey-a")
        let aliasB = uniqueAlias("wrongkey-b")
        defer {
            KekDekManager.shared.deleteKey(alias: aliasA)
            KekDekManager.shared.deleteKey(alias: aliasB)
        }

        let wrapped = try KekDekManager.shared.wrap(alias: aliasA, plaintext: Data("secret".utf8))
        _ = try KekDekManager.shared.wrap(alias: aliasB, plaintext: Data("unrelated".utf8)) // materialize a different key

        #expect(throws: (any Error).self) {
            try KekDekManager.shared.unwrap(alias: aliasB, wrapped: wrapped)
        }
    }

    @Test func importKeyIsUsedInsteadOfGeneratingANewOne() throws {
        let alias = uniqueAlias("import")
        defer { KekDekManager.shared.deleteKey(alias: alias) }

        let rawKey = Data(repeating: 0x42, count: 32)
        KekDekManager.shared.importKey(alias: alias, rawKeyBytes: rawKey)

        let plaintext = Data("imported key roundtrip".utf8)
        let wrapped = try KekDekManager.shared.wrap(alias: alias, plaintext: plaintext)
        let unwrapped = try KekDekManager.shared.unwrap(alias: alias, wrapped: wrapped)

        #expect(unwrapped == plaintext)
    }

    @Test func deleteKeyIsIdempotentAndDestroysUnwrapAbility() throws {
        let alias = uniqueAlias("delete")
        let wrapped = try KekDekManager.shared.wrap(alias: alias, plaintext: Data("x".utf8))

        KekDekManager.shared.deleteKey(alias: alias)
        KekDekManager.shared.deleteKey(alias: alias) // idempotent, no throw

        #expect(!KekDekManager.shared.keyExists(alias: alias))
        #expect(throws: KekDekError.keyNotFound) {
            try KekDekManager.shared.unwrap(alias: alias, wrapped: wrapped)
        }
    }

    // MARK: - Secure Enclave alias dispatch (regression coverage)
    //
    // Real bug found in review: the SE-backed alias set was hardcoded to
    // ONLY the field slot's bootstrap alias, so the image slot's bootstrap
    // KEK silently fell through to the weaker plain-Keychain-AES path
    // instead of Secure Enclave. Fixed by sourcing the SE alias set from
    // `DekSlot.allBootstrapAliases` so every registered slot is covered.
    //
    // These tests assert against `DekSlot.allBootstrapAliases` itself
    // (never wrap/unwrap/delete using those literal aliases directly) —
    // those are the REAL production bootstrap-KEK aliases the app's own
    // singleton uses. Exercising wrap/delete on them here would create or
    // destroy the actual app's SE bootstrap KEK on whatever device/simulator
    // the test runs on, potentially orphaning a real wrapped DEK.

    @Test func everyDekSlotBootstrapAliasIsRegisteredAsSecureEnclaveBacked() {
        // This is the exact defect class that shipped: a new/renamed slot's
        // bootstrap alias silently NOT ending up in the SE set. Assert the
        // wiring directly rather than just behaviorally, since a behavioral
        // wrap/unwrap round-trip succeeds either way (both paths are
        // internally consistent) and would NOT have caught the original bug.
        for alias in [DekSlot.field.bootstrapAlias, DekSlot.image.bootstrapAlias] {
            #expect(DekSlot.allBootstrapAliases.contains(alias))
        }
    }

    @Test func allBootstrapAliasesContainsExactlyOneEntryPerSlot() {
        // Guards against a copy-paste duplicate (both slots accidentally
        // sharing one bootstrap alias) collapsing the set size silently.
        #expect(DekSlot.allBootstrapAliases.count == 2)
        #expect(DekSlot.field.bootstrapAlias != DekSlot.image.bootstrapAlias)
    }

    /// Behavioral confirmation that BOTH registered bootstrap aliases
    /// actually route through the SE/ECIES path (not just that they're
    /// present in the set — `everyDekSlotBootstrapAliasIsRegisteredAs...`
    /// covers that). Uses the real production aliases (there is no other
    /// way to address the SE path — it's keyed by exact alias string) but
    /// ONLY wraps/unwraps, never deletes: `wrap` reuses any existing SE key
    /// at that alias rather than replacing it (getOrCreateSecureEnclaveKey
    /// is idempotent), so this cannot orphan a real app-level wrapped DEK
    /// that happens to already exist under the same alias on this device.
    @Test func productionBootstrapAliasesRouteThroughSecureEnclaveFormat() throws {
        let plaintext = Data(repeating: 0xEE, count: 32)
        for alias in DekSlot.allBootstrapAliases {
            let wrapped = try KekDekManager.shared.wrap(alias: alias, plaintext: plaintext)
            // SE/ECIES format: 65-byte ephemeral public key + 12-byte IV +
            // ciphertext + 16-byte tag — strictly longer than the plain AES
            // format (12 + ciphertext + 16) for the same plaintext size.
            #expect(wrapped.count == 65 + 12 + plaintext.count + 16)

            let unwrapped = try KekDekManager.shared.unwrap(alias: alias, wrapped: wrapped)
            #expect(unwrapped == plaintext)
        }
    }
}
