////
////  TLSIdentityManager.swift
////  PillCounter
////
////  Created by Bhushan Patil on 03/02/26.
////


import Foundation
import Security
import UIKit

final class TLSIdentityManager {

    // MARK: - Constants

    /// Tag burned into the private key item — used to locate it later.
    private static let privateKeyTag = "com.pillcounter.hl7.tls.privkey"

    /// Label on the certificate item — used to locate it later.
    private static let certLabel     = "com.pillcounter.hl7.tls.cert"

    // MARK: - Public API

    /// Returns an existing `SecIdentity` from the Keychain, or generates and
    /// stores a fresh one.  On iOS the Keychain synthesises the identity by
    /// joining a `kSecClassCertificate` row with the `kSecClassKey` row that
    /// shares the same public-key hash — there is no explicit "store identity"
    /// step and `SecIdentityCreateWithCertificate` is macOS-only.
    static func loadOrCreateIdentity() throws -> SecIdentity {
        if let existing = try? fetchIdentity() {
            print("[TLS] Existing identity loaded from Keychain")
            return existing
        }
        print("[TLS] No existing identity — generating new key pair")
        return try generateAndStoreIdentity()
    }

    // MARK: - Export

    /// DER-encoded certificate for this device.
    /// Send to PMS during onboarding so PMS can trust this device.
    static func exportCertificateDER() throws -> Data {
        let identity = try loadOrCreateIdentity()
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess,
              let certificate = cert else {
            throw TLSError.publicKeyExportFailed
        }
        return SecCertificateCopyData(certificate) as Data
    }

    // MARK: - Wipe

    /// Removes all TLS material from the Keychain.
    /// Call only during a full account reset.
    static func deleteStoredIdentity() {
        let tag = privateKeyTag.data(using: .utf8)!

        SecItemDelete([
            kSecClass as String:                kSecClassKey,
            kSecAttrApplicationTag as String:   tag
        ] as CFDictionary)

        SecItemDelete([
            kSecClass as String:        kSecClassCertificate,
            kSecAttrLabel as String:    certLabel
        ] as CFDictionary)

        print("[TLS] Stored identity wiped")
    }

    // MARK: - Fetch

    /// On iOS, querying `kSecClassIdentity` makes the Keychain internally join
    /// the certificate (matched by label) with the private key (matched by the
    /// public-key hash embedded in the certificate) and return a `SecIdentity`.
    /// This only works if both items are already present.
    private static func fetchIdentity() throws -> SecIdentity {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassIdentity,
            kSecAttrLabel as String:    certLabel,
            kSecReturnRef as String:    true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let identity = result else {
            throw TLSError.keychainError(status)
        }

        return (identity as! SecIdentity)
    }

    // MARK: - Generate + Store

    private static func generateAndStoreIdentity() throws -> SecIdentity {
        let tag = privateKeyTag.data(using: .utf8)!

        // ── 1. Clean up any orphaned items from a previous partial attempt ──
        SecItemDelete([
            kSecClass as String:                kSecClassKey,
            kSecAttrApplicationTag as String:   tag,
            kSecAttrKeyType as String:          kSecAttrKeyTypeECSECPrimeRandom
        ] as CFDictionary)

        SecItemDelete([
            kSecClass as String:        kSecClassCertificate,
            kSecAttrLabel as String:    certLabel
        ] as CFDictionary)

        // ── 2. Generate EC P-256 private key in Secure Enclave ──
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            .privateKeyUsage,   // key is non-extractable; stays in hardware
            nil
        )!

        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String:          kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:    256,
            kSecAttrTokenID as String:          kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:      true,
                kSecAttrApplicationTag as String:   tag,
                kSecAttrAccessControl as String:    access
            ]
        ]

        var keyError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &keyError) else {
            throw keyError!.takeRetainedValue()
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw TLSError.publicKeyExportFailed
        }

        print("[TLS] EC P-256 key pair generated in Secure Enclave")

        // ── 3. Build self-signed certificate ──
        let cert = try SelfSignedCertBuilder.build(publicKey: publicKey, privateKey: privateKey)
        print("[TLS] Self-signed certificate built")

        // ── 4. Store certificate ──
        // The Keychain links the cert to the private key automatically by
        // matching the public-key hash embedded in both items.
        // kSecAttrLabel lets us find it again via kSecClassIdentity query.
        let addCert: [String: Any] = [
            kSecClass as String:            kSecClassCertificate,
            kSecValueRef as String:         cert,
            kSecAttrLabel as String:        certLabel,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let certStatus = SecItemAdd(addCert as CFDictionary, nil)
        guard certStatus == errSecSuccess || certStatus == errSecDuplicateItem else {
            throw TLSError.keychainError(certStatus)
        }

        print("[TLS] Certificate stored in Keychain")

        // ── 5. Resolve identity via kSecClassIdentity query ──
        // Now that both the key (permanent, tagged) and cert (labelled) are
        // present, the Keychain can join them and return a SecIdentity.
        return try fetchIdentity()
    }
}

// MARK: - Errors

enum TLSError: Error, LocalizedError {
    case publicKeyExportFailed
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .publicKeyExportFailed:
            return "Failed to export public key from Secure Enclave"
        case .keychainError(let status):
            return "Keychain error \(status): \(status.keychainDescription)"
        }
    }
}

// MARK: - OSStatus readable description

extension OSStatus {
    var keychainDescription: String {
        switch self {
        case errSecSuccess:               return "success"
        case errSecItemNotFound:          return "item not found"
        case errSecDuplicateItem:         return "duplicate item"
        case errSecAuthFailed:            return "auth failed"
        case errSecParam:                 return "invalid param"
        case errSecAllocate:              return "allocation failed"
        case errSecNotAvailable:          return "not available"
        case errSecInteractionNotAllowed: return "interaction not allowed"
        default:                          return "OSStatus(\(self))"
        }
    }
}




//
//import Foundation
//import Security
//import CoreData
//
//final class TLSIdentityManager {
//
//    static func loadIdentity() throws -> SecIdentity {
//
//        guard let url = Bundle.main.url(forResource: "android-server", withExtension: "p12"),
//              let data = try? Data(contentsOf: url) else {
//            throw NSError(domain: "TLS", code: -1, userInfo: [
//                NSLocalizedDescriptionKey: "android-server not found"
//            ])
//        }
//
//        let options: [String: Any] = [
//            kSecImportExportPassphrase as String: "rite"
//        ]
//
//        var items: CFArray?
//        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
//
//        guard status == errSecSuccess else {
//            throw NSError(domain: "TLS", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to import PKCS#12: status \(status)"])
//        }
//
//        guard let itemsArray = items as? [[String: Any]], let firstItem = itemsArray.first else {
//            throw NSError(domain: "TLS", code: -2, userInfo: [NSLocalizedDescriptionKey: "PKCS#12 import returned no items"])
//        }
//
//        guard let identityAny = firstItem[kSecImportItemIdentity as String] else {
//            throw NSError(domain: "TLS", code: -3, userInfo: [NSLocalizedDescriptionKey: "No identity found in PKCS#12 import result"])
//        }
//
//        let identity = identityAny as! SecIdentity
//        return identity
//    }
//}
//

//
//  TLSIdentityManager.swift
//  PillCounter
//

//
//  TLSIdentityManager.swift
//  PillCounter
//
