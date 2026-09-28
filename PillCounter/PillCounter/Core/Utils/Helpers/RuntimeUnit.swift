//
//  RuntimeUnit.swift
//  PillCounter
//
//  Created by HC on 13/01/26.
//

import CryptoKit
import Foundation
import Security

struct RuntimeUnit {

    // MARK: - PUBLIC INTERFACE

    /// BOOTSTRAP
    /// Initializes and securely stores the protected material if it does not already exist.
    static func activateIfNeeded() throws {
        guard !existsInStore() else { return }

        let raw = compose()
        let refined = refine(raw)
        let sealed = try seal(refined)

        persist(sealed)
        destroy(refined)
    }

    /// MATERIAL
    /// Retrieves and decrypts the stored value for runtime usage.
    static func material() throws -> String {
        let sealed = try retrieve()
        return try open(sealed)
    }

    // MARK: - ASSEMBLY

    /// COMPOSE
    /// Builds the raw value by joining multiple obfuscated fragments.
    private static func compose() -> String {
        let parts = [
            f1(), f2(), f3(), f4(), f5(), f6(),
        ]
        return parts.joined()
    }

    /// REFINE
    /// Removes noise characters to produce the final runtime value.
    private static func refine(_ value: String) -> String {
        value.filter {
            $0.isLetter || $0.isNumber
        }
    }

    /// DESTROY
    /// Attempts to overwrite the temporary plaintext buffer after use.
    private static func destroy(_ value: String) {
        guard var data = value.data(using: .utf8) else { return }

        data.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress {
                memset(base, 0, buffer.count)
            }
        }
    }

    // MARK: - FRAGMENTS

    /// FRAGMENT
    /// Returns a partial, noisy component of the protected value.
    private static func f1() -> String {
        "_d1@#$ff4797@#$ac_b714@#%#^7205bb249#$%$%cce9"
    }

    /// FRAGMENT
    /// Returns a partial, noisy component of the protected value.
    private static func f2() -> String {
        "-_18f)23a4*(f%%8e&^#54a8"
    }

    /// FRAGMENT
    /// Returns a partial, noisy component of the protected value.
    private static func f3() -> String {
        "_d5648@#%^8d79e83^&%$abcdf1*$@b24f6f1^*cc&"
    }

    /// FRAGMENT
    /// Returns a partial, noisy component of the protected value.
    private static func f4() -> String {
        "-c9+af%@*5dea#@&3c^@!1a1b^@!5e2b#^(%6"
    }

    /// FRAGMENT
    /// Returns a partial, noisy component of the protected value.
    private static func f5() -> String {
        "_a-a2-4-7@#$^*^ff55ac8e12#$^%*f165974&*"
    }

    /// FRAGMENT
    /// Returns a partial, noisy component of the protected value.
    private static func f6() -> String { "_f#$^%*&8cf#$%^*(ce41328^#&)(f7ea447e$#&" }

    // MARK: - SECURE ENCLAVE

    /// IDENTIFIER
    /// Application-specific tag used to locate the Secure Enclave key.
    private static let enclaveTag =
        "com.runtime.unit.node".data(using: .utf8)!

    /// ENCLAVE KEY
    /// Fetches or creates a hardware-backed Secure Enclave key.
    private static func enclaveKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: enclaveTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess {
            // kSecReturnRef + a kSecClassKey query should guarantee a single SecKey,
            // but check the concrete type rather than force-casting so a future query
            // change that widens the match fails safe instead of crashing.
            guard let item, CFGetTypeID(item) == SecKeyGetTypeID() else {
                throw KeychainTypeError(reason: "Unexpected Keychain item type for Enclave key")
            }
            return (item as! SecKey)
        }

        var accessError: Unmanaged<CFError>?
        guard let access =
            SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.privateKeyUsage],
                &accessError
            )
        else {
            if let accessError { throw accessError.takeRetainedValue() }
            throw KeychainTypeError(reason: "Access Control Creation Failed")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: enclaveTag,
                kSecAttrAccessControl as String: access,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard
            let key =
                SecKeyCreateRandomKey(attributes as CFDictionary, &error)
        else {
            throw error!.takeRetainedValue()
        }

        return key
    }

    private struct SealError: Error { let reason: String }
    private struct KeychainTypeError: Error { let reason: String }

    /// SEAL
    /// Encrypts the value using the Secure Enclave key.
    private static func seal(_ value: String) throws -> Data {
        // 1. Get the Private Key safely
        let privateKey: SecKey
        do {
            privateKey = try enclaveKey()
        } catch {
            AppLogger.shared.error("RuntimeUnit: failed to retrieve Enclave Key", error: error, event: .securityCheckFailed)
            throw SealError(reason: "Missing Key")
        }

        // 2. Extract the Public Key from the Private Key
        // Encryption is a Public Key operation. The Secure Enclave requires this explicit step.
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            AppLogger.shared.error("RuntimeUnit: failed to generate Public Key from Private Key", event: .securityCheckFailed)
            throw SealError(reason: "Public Key Generation Failed")
        }

        guard let data = value.data(using: .utf8) else {
            AppLogger.shared.error("RuntimeUnit: failed to encode refined value as UTF-8", event: .securityCheckFailed)
            throw SealError(reason: "Encoding Failed")
        }

        var error: Unmanaged<CFError>?

        // 3. Encrypt using the PUBLIC Key
        guard
            let encrypted = SecKeyCreateEncryptedData(
                publicKey,
                .eciesEncryptionStandardX963SHA256AESGCM,
                data as CFData,
                &error
            )
        else {
            let err = error!.takeRetainedValue() as Error
            AppLogger.shared.error("RuntimeUnit: encryption failed", error: err, event: .securityCheckFailed)
            throw SealError(reason: "Encryption Failed")
        }

        return encrypted as Data
    }

    /// OPEN
    /// Decrypts the stored data using the Secure Enclave key.
    private static func open(_ data: Data) throws -> String {
        let key = try enclaveKey()

        var error: Unmanaged<CFError>?
        guard
            let decrypted =
                SecKeyCreateDecryptedData(
                    key,
                    .eciesEncryptionStandardX963SHA256AESGCM,
                    data as CFData,
                    &error
                )
        else {
            throw error!.takeRetainedValue()
        }

        return String(decoding: decrypted as Data, as: UTF8.self)
    }

    // MARK: - STORAGE

    /// IDENTIFIER
    /// Keychain account identifier for the stored encrypted payload.
    private static let storageID = "runtime_unit_payload_v3"

    /// EXISTS
    /// Checks whether the encrypted payload already exists in the Keychain.
    private static func existsInStore() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: storageID,
            kSecReturnData as String: false,
        ]

        return SecItemCopyMatching(
            query as CFDictionary,
            nil
        ) == errSecSuccess
    }

    /// PERSIST
    /// Stores the encrypted payload securely in the Keychain.
    private static func persist(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: storageID,
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    /// RETRIEVE
    /// Fetches the encrypted payload from the Keychain.
    private static func retrieve() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: storageID,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        guard
            SecItemCopyMatching(
                query as CFDictionary,
                &item
            ) == errSecSuccess
        else {
            throw NSError(domain: "unit", code: -1)
        }

        guard let data = item as? Data else {
            throw KeychainTypeError(reason: "Unexpected Keychain item type for stored payload")
        }
        return data
    }
}
