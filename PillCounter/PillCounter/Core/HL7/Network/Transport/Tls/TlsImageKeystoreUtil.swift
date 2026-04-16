////
////  TlsImageKeystoreUtil.swift
////  PillCounter
////
////  Created by Bhushan Patil on 09/02/26.
////

import Foundation
import Security
import CryptoKit

/// Manages the TLS identity used by the HTTPS image server.
///
/// Production approach — no bundled .p12, no hardcoded password:
///   • EC P-256 private key generated on-device in the Secure Enclave (non-extractable)
///   • Self-signed certificate built via SelfSignedCertBuilder and stored in Keychain
///   • Identity resolved by querying kSecClassIdentity (iOS Keychain joins cert + key
///     automatically via the public-key hash — SecIdentityCreateWithCertificate is macOS-only)
///   • Separate Keychain tags from TLSIdentityManager so the two identities never collide
///   • Fingerprint derived from live Keychain cert via CryptoKit SHA-256 (no CommonCrypto)
final class TlsImageKeystoreUtil {

    static let shared = TlsImageKeystoreUtil()

    // MARK: - Keychain tags (must differ from TLSIdentityManager's tags)

    private let privateKeyTag = "com.pillcounter.imageserver.tls.privkey"
    private let certLabel     = "com.pillcounter.imageserver.tls.cert"

    private init() {}

    // MARK: - Public API

    /// Returns an existing identity or generates a fresh one.
    /// Never returns nil in production — throws internally and prints diagnostics.
    func ensureIdentity() -> SecIdentity? {
        do {
            return try loadOrCreateIdentity()
        } catch {
            print("[ImageTLS] ❌ Failed to ensure identity: \(error.localizedDescription)")
            return nil
        }
    }

    /// SHA-256 fingerprint of the server certificate, colon-separated uppercase hex.
    /// Used by C# clients to pin the server certificate on first connection.
    func getFingerprint() -> String {
        guard let identity = ensureIdentity() else { return "" }
        var certRef: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certRef) == errSecSuccess,
              let cert = certRef else { return "" }
        let derData = SecCertificateCopyData(cert) as Data
        let digest = SHA256.hash(data: derData)
        return digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Removes all image-server TLS material from the Keychain.
    /// Call during a full account reset — the next call to ensureIdentity()
    /// will generate a new key pair and certificate.
    func deleteStoredIdentity() {
        let tag = privateKeyTag.data(using: .utf8)!
        SecItemDelete([
            kSecClass as String:                kSecClassKey,
            kSecAttrApplicationTag as String:   tag
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String:        kSecClassCertificate,
            kSecAttrLabel as String:    certLabel
        ] as CFDictionary)
        print("[ImageTLS] Stored identity wiped")
    }

    // MARK: - Load or Create

    private func loadOrCreateIdentity() throws -> SecIdentity {
        if let existing = try? fetchIdentity() {
            print("[ImageTLS] ✅ Existing identity loaded from Keychain")
            return existing
        }
        print("[ImageTLS] ⚠️ No existing identity — generating new key pair")
        return try generateAndStoreIdentity()
    }

    // MARK: - Fetch

    /// Queries kSecClassIdentity — the Keychain joins the stored certificate
    /// with the private key (matched by public-key hash) and returns SecIdentity.
    /// Both items must already be present for this to succeed.
    private func fetchIdentity() throws -> SecIdentity {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassIdentity,
            kSecAttrLabel as String:    certLabel,
            kSecReturnRef as String:    true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let ref = result else {
            throw ImageTLSError.keychainError(status)
        }
        // swiftlint:disable:next force_cast
        return (ref as! SecIdentity)
    }

    // MARK: - Generate + Store

    private func generateAndStoreIdentity() throws -> SecIdentity {
        let tag = privateKeyTag.data(using: .utf8)!

        // ── 1. Remove any orphaned items from a previous partial attempt ──
        SecItemDelete([
            kSecClass as String:                kSecClassKey,
            kSecAttrApplicationTag as String:   tag,
            kSecAttrKeyType as String:          kSecAttrKeyTypeECSECPrimeRandom
        ] as CFDictionary)

        SecItemDelete([
            kSecClass as String:        kSecClassCertificate,
            kSecAttrLabel as String:    certLabel
        ] as CFDictionary)

        // ── 2. Generate EC P-256 key pair in Secure Enclave ──
        //
        // .privateKeyUsage keeps the private key non-extractable — it
        // never leaves the Secure Enclave, even if the device is compromised.
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            .privateKeyUsage,
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
            throw ImageTLSError.publicKeyExportFailed
        }

        print("[ImageTLS] EC P-256 key pair generated in Secure Enclave")

        // ── 3. Build self-signed certificate ──
        let cert = try SelfSignedCertBuilder.build(publicKey: publicKey, privateKey: privateKey)
        print("[ImageTLS] Self-signed certificate built")

        // ── 4. Store certificate in Keychain ──
        //
        // The Keychain links this cert to the private key automatically
        // by matching the public-key hash embedded in both items.
        // kSecAttrLabel is how fetchIdentity() locates it later.
        let addCert: [String: Any] = [
            kSecClass as String:            kSecClassCertificate,
            kSecValueRef as String:         cert,
            kSecAttrLabel as String:        certLabel,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let certStatus = SecItemAdd(addCert as CFDictionary, nil)
        guard certStatus == errSecSuccess || certStatus == errSecDuplicateItem else {
            throw ImageTLSError.keychainError(certStatus)
        }

        print("[ImageTLS] Certificate stored in Keychain")

        // ── 5. Resolve identity via kSecClassIdentity ──
        return try fetchIdentity()
    }
}

// MARK: - Errors

private enum ImageTLSError: Error, LocalizedError {
    case publicKeyExportFailed
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .publicKeyExportFailed:
            return "[ImageTLS] Failed to export public key from Secure Enclave"
        case .keychainError(let s):
            return "[ImageTLS] Keychain error: \(s.keychainDescription)"
        }
    }
}






//import Foundation
//import Security
//import CommonCrypto
//
//class TlsImageKeystoreUtil {
//
//    static let shared = TlsImageKeystoreUtil()
//
//    private let password = "rite"
//    private let alias = "image_https"
//
//    private init() {}
//
//    // MARK: - Public
//
//    func ensureIdentity() -> SecIdentity? {
//        if let identity = loadIdentityFromKeychain() {
//            print("✅ Loaded identity from keychain")
//            return identity
//        }
//
//        print("⚠️ Identity not found → loading from p12")
//        return loadFromP12AndStore()
//    }
//
//    func getFingerprint() -> String {
//        guard let identity = ensureIdentity(),
//              let cert = getCertificate(from: identity) else {
//            return ""
//        }
//
//        let data = SecCertificateCopyData(cert) as Data
//        return sha256(data)
//    }
//
//    // MARK: - Keychain
//
//    private func loadIdentityFromKeychain() -> SecIdentity? {
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassIdentity,
//            kSecAttrLabel as String: alias,
//            kSecReturnRef as String: true
//        ]
//
//        var item: CFTypeRef?
//        let status = SecItemCopyMatching(query as CFDictionary, &item)
//
//        if status == errSecSuccess {
//            return item as! SecIdentity
//        }
//
//        return nil
//    }
//
//    private func loadFromP12AndStore() -> SecIdentity? {
//        guard let url = Bundle.main.url(forResource: "ios-server", withExtension: "p12"),
//              let data = try? Data(contentsOf: url) else {
//            print("❌ Failed to load p12 file")
//            return nil
//        }
//
//        let options: [String: Any] = [
//            kSecImportExportPassphrase as String: password
//        ]
//
//        var items: CFArray?
//
//        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
//
//        guard status == errSecSuccess,
//              let array = items as? [[String: Any]],
//              let identityRef = array.first?[kSecImportItemIdentity as String] else {
//            print("❌ PKCS12 import failed:", status)
//            return nil
//        }
//
//        let identity = identityRef as! SecIdentity
//
//        // 🔥 Store in keychain (important)
//        storeIdentity(identity)
//
//        return identity
//    }
//
//    private func storeIdentity(_ identity: SecIdentity) {
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassIdentity,
//            kSecAttrLabel as String: alias,
//            kSecValueRef as String: identity
//        ]
//
//        SecItemDelete(query as CFDictionary)
//        let status = SecItemAdd(query as CFDictionary, nil)
//
//        print("🔐 Store identity status:", status)
//    }
//
//    // MARK: - Helpers
//
//    private func getCertificate(from identity: SecIdentity) -> SecCertificate? {
//        var cert: SecCertificate?
//        SecIdentityCopyCertificate(identity, &cert)
//        return cert
//    }
//
//    private func sha256(_ data: Data) -> String {
//        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//
//        data.withUnsafeBytes {
//            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
//        }
//
//        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
//    }
//}

//
//  TlsImageKeystoreUtil.swift
//  PillCounter
//
