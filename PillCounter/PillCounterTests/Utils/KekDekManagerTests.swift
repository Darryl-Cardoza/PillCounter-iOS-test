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
        _ = KekDekManager.shared.getOrCreateKey(alias: aliasB) // materialize a different key

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
}
