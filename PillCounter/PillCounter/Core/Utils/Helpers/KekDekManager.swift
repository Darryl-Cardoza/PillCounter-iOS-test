//
//  KekDekManager.swift
//  PillCounter
//
//  Envelope-encryption primitive: wrap/unwrap a key (the DEK) under a KEK
//  identified by an alias. Two KEK backings, matching what's actually
//  achievable on each side of the KEK lifecycle:
//
//  • Bootstrap KEK (`bootstrapAlias`, device-generated): backed by a Secure
//    Enclave P256 key pair. The SE key itself never leaves hardware and is
//    never extractable — same non-extractability guarantee as an Android
//    Keystore key. Since the SE only does EC key agreement (no raw AES, no
//    imported key material), wrap/unwrap here is ECIES-shaped: an ephemeral
//    P256 key agrees with the SE key over ECDH, HKDF-derives an AES-256 key
//    from the shared secret, and that derived key does the actual AES-GCM
//    seal/open. The ephemeral public key travels alongside the ciphertext
//    (needed to redo the same ECDH on unwrap) — it is not secret.
//
//  • Server-issued KEK (`server_kek_*` aliases): arrives over the wire as
//    raw AES-256 bytes (`/auth/me` → `kek.key_material`). The Secure Enclave
//    cannot import external key material on any iOS version — there is no
//    hardware-backed home for this key. It is held as a CryptoKit
//    `SymmetricKey` in the Keychain (`WhenUnlockedThisDeviceOnly`), which is
//    Keychain-at-rest protection but not SE non-extractability. This is a
//    platform ceiling, not an oversight — document it as such wherever this
//    matters (e.g. security review).
//
//  Wire/wrapped format:
//   - Server (AES) path:      IV (12 bytes) || ciphertext || 16-byte GCM tag
//   - Bootstrap (SE/ECIES) path: ephemeralPublicKeyX963 (65 bytes, uncompressed
//     P256 point) || IV (12 bytes) || ciphertext || 16-byte GCM tag
//  Callers never need to know which shape applies — `wrap`/`unwrap` dispatch
//  on the alias.
//

import CryptoKit
import Foundation
import Security

enum KekDekError: Error {
    case keyNotFound
    case secureEnclaveKeyGenerationFailed(OSStatus)
    case malformedWrappedData
    case keyAgreementFailed
}

final class KekDekManager {

    static let shared = KekDekManager()
    private init() {}

    private static let service = Keychain.defaultService
    private static let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    /// Aliases that are backed by a Secure Enclave key pair rather than a
    /// plain Keychain symmetric key. Currently just the device-local
    /// bootstrap KEK — server-issued KEKs can never be SE-backed (see file
    /// header) so they always go through the AES/Keychain path below.
    private static let secureEnclaveAliasPrefix = "com.pillcounter.database.dek_bootstrap_kek"

    private func isSecureEnclaveBacked(alias: String) -> Bool {
        alias == Self.secureEnclaveAliasPrefix
    }

    // MARK: - Public API (dispatches by alias)

    /// Encrypts `plaintext` under the key for `alias` (creating the key if
    /// needed).
    func wrap(alias: String, plaintext: Data) throws -> Data {
        if isSecureEnclaveBacked(alias: alias) {
            return try wrapWithSecureEnclave(alias: alias, plaintext: plaintext)
        }
        return try wrapWithKeychainAES(alias: alias, plaintext: plaintext)
    }

    /// Decrypts `wrapped` using the key stored under `alias`. Never creates
    /// a key on unwrap — a missing alias is a hard failure, not a silent
    /// fresh key.
    func unwrap(alias: String, wrapped: Data) throws -> Data {
        if isSecureEnclaveBacked(alias: alias) {
            return try unwrapWithSecureEnclave(alias: alias, wrapped: wrapped)
        }
        return try unwrapWithKeychainAES(alias: alias, wrapped: wrapped)
    }

    /// Imports raw key bytes (e.g. server-issued KEK material) into the
    /// Keychain under `alias`, overwriting any existing item. `rawKeyBytes`
    /// is not mutated here — callers that hold a mutable buffer should zero
    /// it themselves immediately after this returns. Never used for the
    /// Secure Enclave alias — SE keys are generated in hardware, never
    /// imported.
    func importKey(alias: String, rawKeyBytes: Data) {
        Keychain.setData(
            rawKeyBytes,
            account: alias,
            service: Self.service,
            accessibility: Self.accessibility
        )
    }

    /// Deletes the key stored under `alias` (SE private key reference or
    /// plain Keychain symmetric key, whichever applies). Idempotent — a
    /// no-op if absent.
    func deleteKey(alias: String) {
        if isSecureEnclaveBacked(alias: alias) {
            SecItemDelete([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: seKeyTag(alias: alias),
            ] as CFDictionary)
            return
        }
        Keychain.deleteData(account: alias, service: Self.service)
    }

    func keyExists(alias: String) -> Bool {
        if isSecureEnclaveBacked(alias: alias) {
            return loadSecureEnclaveKey(alias: alias) != nil
        }
        return Keychain.data(account: alias, service: Self.service) != nil
    }

    // MARK: - AES/Keychain path (server-issued KEKs, and any non-SE alias)

    private func getOrCreateAESKey(alias: String) -> SymmetricKey {
        Keychain.getOrCreateSymmetricKey(
            account: alias,
            service: Self.service,
            accessibility: Self.accessibility
        )
    }

    private func wrapWithKeychainAES(alias: String, plaintext: Data) throws -> Data {
        let key = getOrCreateAESKey(alias: alias)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw KekDekError.keyNotFound
        }
        return combined
    }

    private func unwrapWithKeychainAES(alias: String, wrapped: Data) throws -> Data {
        guard Keychain.data(account: alias, service: Self.service) != nil else {
            throw KekDekError.keyNotFound
        }
        let key = getOrCreateAESKey(alias: alias)
        let sealed = try AES.GCM.SealedBox(combined: wrapped)
        return try AES.GCM.open(sealed, using: key)
    }

    // MARK: - Secure Enclave / ECIES path (bootstrap KEK only)

    private func seKeyTag(alias: String) -> Data {
        Data((alias + ".se").utf8)
    }

    /// Loads the SE private key reference for `alias`, or nil if it hasn't
    /// been generated yet. This is a `SecKey` reference — the actual key
    /// material never leaves the Secure Enclave and is never readable, by
    /// design (matches Android Keystore's non-extractability).
    private func loadSecureEnclaveKey(alias: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: seKeyTag(alias: alias),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return (result as! SecKey)
    }

    private func getOrCreateSecureEnclaveKey(alias: String) throws -> SecKey {
        if let existing = loadSecureEnclaveKey(alias: alias) {
            return existing
        }

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &error
        ) else {
            throw KekDekError.secureEnclaveKeyGenerationFailed(errSecParam)
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: seKeyTag(alias: alias),
                kSecAttrAccessControl as String: access,
            ],
        ]

        var createError: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &createError) else {
            throw KekDekError.secureEnclaveKeyGenerationFailed(errSecParam)
        }
        return key
    }

    /// ECIES-shaped wrap: ephemeral P256 keypair ECDH's with the SE public
    /// key, HKDF-derives an AES-256 key from the shared secret, and that key
    /// AES-GCM-seals `plaintext`. The ephemeral public key is prepended to
    /// the output (it's not secret — unwrap needs it to redo the same ECDH).
    private func wrapWithSecureEnclave(alias: String, plaintext: Data) throws -> Data {
        let sePrivateKey = try getOrCreateSecureEnclaveKey(alias: alias)
        guard let sePublicKey = SecKeyCopyPublicKey(sePrivateKey) else {
            throw KekDekError.keyAgreementFailed
        }
        let sePublicKeyData = try externalRepresentation(of: sePublicKey)
        let seP256PublicKey = try P256.KeyAgreement.PublicKey(x963Representation: sePublicKeyData)

        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: seP256PublicKey)
        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("com.pillcounter.kekdek.se".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let sealed = try AES.GCM.seal(plaintext, using: derivedKey)
        guard let combined = sealed.combined else {
            throw KekDekError.keyAgreementFailed
        }

        return ephemeralPrivateKey.publicKey.x963Representation + combined
    }

    /// Reverses `wrapWithSecureEnclave`: reads the ephemeral public key back
    /// out of `wrapped`, ECDH's it against the SE *private* key (the one
    /// operation the Secure Enclave actually performs in hardware — the
    /// private key material itself is never exposed to this process), and
    /// AES-GCM-opens the remainder with the same HKDF-derived key.
    private func unwrapWithSecureEnclave(alias: String, wrapped: Data) throws -> Data {
        guard let sePrivateKey = loadSecureEnclaveKey(alias: alias) else {
            throw KekDekError.keyNotFound
        }

        let ephemeralPublicKeyLength = 65 // uncompressed P256 point: 0x04 || X(32) || Y(32)
        guard wrapped.count > ephemeralPublicKeyLength else {
            throw KekDekError.malformedWrappedData
        }
        let ephemeralPublicKeyData = wrapped.prefix(ephemeralPublicKeyLength)
        let combined = wrapped.dropFirst(ephemeralPublicKeyLength)

        // Re-validates the point (throws if malformed) and gets us a value
        // whose x963Representation is the canonical encoding to hand to
        // SecKeyCreateWithData below.
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: ephemeralPublicKeyData)

        let ephemeralSecKeyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var importError: Unmanaged<CFError>?
        guard let ephemeralSecKey = SecKeyCreateWithData(
            ephemeralPublicKey.x963Representation as CFData,
            ephemeralSecKeyAttributes as CFDictionary,
            &importError
        ) else {
            throw KekDekError.keyAgreementFailed
        }

        var agreementError: Unmanaged<CFError>?
        let params: [String: Any] = [
            SecKeyKeyExchangeParameter.requestedSize.rawValue as String: 32,
        ]
        guard let sharedSecretData = SecKeyCopyKeyExchangeResult(
            sePrivateKey,
            .ecdhKeyExchangeStandard,
            ephemeralSecKey,
            params as CFDictionary,
            &agreementError
        ) as Data? else {
            throw KekDekError.keyAgreementFailed
        }

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sharedSecretData),
            salt: Data("com.pillcounter.kekdek.se".utf8),
            info: Data(),
            outputByteCount: 32
        )

        let sealed = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealed, using: derivedKey)
    }

    private func externalRepresentation(of key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw KekDekError.keyAgreementFailed
        }
        return data
    }
}
