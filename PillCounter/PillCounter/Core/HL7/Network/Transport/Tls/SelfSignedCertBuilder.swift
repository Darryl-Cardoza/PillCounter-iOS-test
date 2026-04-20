//
//  SelfSignedCertBuilder.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/04/26.
//


/// Builds a minimal self-signed X.509 v3 certificate from a key pair generated
/// in the Secure Enclave. Apple provides no public API for this, so we hand-encode
/// the DER structure (ASN.1) and sign it with the private key.
///
/// The certificate is intentionally minimal — it carries only what TLS requires:
///   - Subject / Issuer  (CN = device UUID)
///   - Validity          (10 years)
///   - Public key        (EC P-256)
///   - Basic Constraints (not a CA)
///   - Signature         (ES256 over the TBSCertificate)
///
/// This is accepted by NWListener / NWConnection for local mTLS.
/// It is NOT suitable for public PKI or App Store distribution.
//
//  SelfSignedCertBuilder.swift
//  PillCounter
//


//
//  SelfSignedCertBuilder.swift
//  PillCounter
//

import Foundation
import Security
import CryptoKit
import UIKit
import CommonCrypto

/// Builds a minimal self-signed X.509 v3 certificate accepted by iOS TLS stack.
///
/// Two fixes vs previous version:
///
/// Fix 1 — SubjectKeyIdentifier (SKI) extension is now included.
///   Apple's TLS stack requires SKI to be present in any certificate used
///   as a server identity via NWListener. Without it, SecCertificateCreateWithData
///   may succeed but the TLS handshake fails silently.
///   SKI value = SHA-1 of the raw public key bytes (RFC 5280 §4.2.1.2, method 1).
///
/// Fix 2 — Signing uses `ecdsaSignatureDigestX962SHA256` with a pre-computed
///   SHA-256 hash, NOT `ecdsaSignatureMessageX962SHA256`.
///   The "Message" variant instructs the Security framework to hash internally,
///   but on certain Secure Enclave firmware versions this results in a double-hash
///   (SHA-256 of SHA-256), producing a signature that verifies correctly against
///   the wrong data and causes SecCertificateCreateWithData to return nil.
enum SelfSignedCertBuilder {

    enum BuildError: Error, LocalizedError {
        case publicKeyExportFailed(String)
        case signingFailed(String)
        case certCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .publicKeyExportFailed(let r): return "Public key export failed: \(r)"
            case .signingFailed(let r):         return "Signing failed: \(r)"
            case .certCreationFailed(let r):    return "SecCertificateCreateWithData failed — DER prefix: \(r)"
            }
        }
    }

    // MARK: - Public API

    static func build(publicKey: SecKey, privateKey: SecKey) throws -> SecCertificate {
        let cn = "PillCounter-\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"

        // Export raw EC public key bytes.
        // SecKeyCopyExternalRepresentation on a Secure Enclave *public* key returns
        // the uncompressed EC point: 04 || X || Y (65 bytes for P-256).
        var exportError: Unmanaged<CFError>?
        guard let exported = SecKeyCopyExternalRepresentation(publicKey, &exportError) as Data? else {
            let desc = exportError?.takeRetainedValue().localizedDescription ?? "nil"
            throw BuildError.publicKeyExportFailed(desc)
        }

        // Normalise: some platforms return 64 bytes omitting the 0x04 prefix.
        let pubKeyBytes: Data
        switch exported.count {
        case 65 where exported[0] == 0x04:
            pubKeyBytes = exported
        case 64:
            pubKeyBytes = Data([0x04]) + exported
        default:
            throw BuildError.publicKeyExportFailed(
                "Unexpected length \(exported.count), prefix \(exported.first ?? 0)"
            )
        }

        // Build TBSCertificate
        let tbs = buildTBS(cn: cn, publicKeyBytes: pubKeyBytes)

        // Sign: hash TBS with SHA-256 first, then sign the digest.
        // Using ecdsaSignatureDigestX962SHA256 (sign a pre-hashed digest)
        // avoids the double-hash issue present in some SE firmware versions.
        let tbsDigest = Data(SHA256.hash(data: tbs))
        let signature = try sign(digest: tbsDigest, privateKey: privateKey)

        // Assemble full Certificate DER
        let certDER = buildCertificate(tbs: tbs, signature: signature)

        guard let cert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            let prefix = certDER.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
            throw BuildError.certCreationFailed(prefix)
        }

        return cert
    }

    // MARK: - TBSCertificate  (RFC 5280 §4.1)

    private static func buildTBS(cn: String, publicKeyBytes: Data) -> Data {
        // version [0] EXPLICIT INTEGER 2  →  v3
        let version = ctx(0xA0, integer([0x02]))

        // serialNumber — 8 random positive bytes
        var serialBytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, 8, &serialBytes)
        serialBytes[0] &= 0x7F   // clear high bit — keeps INTEGER positive without 0x00 pad
        let serialNumber = integer(serialBytes)

        // signature AlgorithmIdentifier — ecdsa-with-SHA256, no parameters (RFC 5758 §3.2)
        let sigAlg = ecdsaWithSHA256AlgID()

        // issuer == subject (self-signed)
        let dn = buildDN(cn: cn)

        // validity: now → +10 years (both within 2050 so UTCTime is correct)
        let now    = Date()
        let expiry = Calendar.current.date(byAdding: .year, value: 10, to: now)!
        let validity = seq(utctime(now) + utctime(expiry))

        // SubjectPublicKeyInfo
        let spki = buildSPKI(publicKeyBytes: publicKeyBytes)

        // Extensions
        let exts = ctx(0xA3, seq(
            buildBasicConstraintsExtension() +
            buildSubjectKeyIdentifierExtension(publicKeyBytes: publicKeyBytes)
        ))

        return seq(version + serialNumber + sigAlg + dn + validity + dn + spki + exts)
    }

    // MARK: - Full Certificate

    private static func buildCertificate(tbs: Data, signature: Data) -> Data {
        // Certificate ::= SEQUENCE { TBSCertificate, AlgorithmIdentifier, BIT STRING }
        seq(tbs + ecdsaWithSHA256AlgID() + bitstring(signature))
    }

    // MARK: - Signing

    private static func sign(digest: Data, privateKey: SecKey) throws -> Data {
        // ecdsaSignatureDigestX962SHA256: Security signs a pre-hashed SHA-256 digest.
        // The result is a DER-encoded SEQUENCE { INTEGER r, INTEGER s } — exactly
        // what X.509 signatureValue expects inside the BIT STRING.
        let algorithm = SecKeyAlgorithm.ecdsaSignatureDigestX962SHA256

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw BuildError.signingFailed("Algorithm not supported by this key")
        }

        var signError: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(
            privateKey, algorithm, digest as CFData, &signError
        ) as Data? else {
            let desc = signError?.takeRetainedValue().localizedDescription ?? "nil"
            throw BuildError.signingFailed(desc)
        }

        return sig
    }

    // MARK: - X.509 Structures

    /// AlgorithmIdentifier: SEQUENCE { OID(ecdsa-with-SHA256) }
    /// No parameters field per RFC 5758 §3.2.
    private static func ecdsaWithSHA256AlgID() -> Data {
        seq(oid("1.2.840.10045.4.3.2"))
    }

    /// SubjectPublicKeyInfo for EC P-256
    private static func buildSPKI(publicKeyBytes: Data) -> Data {
        let algID = seq(oid("1.2.840.10045.2.1") + oid("1.2.840.10045.3.1.7"))
        return seq(algID + bitstring(publicKeyBytes))
    }

    /// RDNSequence: SEQUENCE { SET { SEQUENCE { OID(CN), UTF8String } } }
    private static func buildDN(cn: String) -> Data {
        seq(set_(seq(oid("2.5.4.3") + utf8str(cn))))
    }

    /// BasicConstraints: id-ce-basicConstraints, value = SEQUENCE {} (cA=FALSE default)
    private static func buildBasicConstraintsExtension() -> Data {
        seq(oid("2.5.29.19") + octetstr(seq(Data())))
    }

    /// SubjectKeyIdentifier: id-ce-subjectKeyIdentifier, value = SHA-1 of raw public key bytes.
    /// RFC 5280 §4.2.1.2 method 1: SKI = SHA-1(BIT STRING content, i.e. the key bytes).
    /// Required by Apple's TLS stack for NWListener server identities.
    private static func buildSubjectKeyIdentifierExtension(publicKeyBytes: Data) -> Data {
        // SHA-1 of the raw EC point bytes (not the BIT STRING wrapper)
        var digest = [UInt8](repeating: 0, count: 20)
        publicKeyBytes.withUnsafeBytes { ptr in
            var ctx = CC_SHA1_CTX()
            CC_SHA1_Init(&ctx)
            CC_SHA1_Update(&ctx, ptr.baseAddress, CC_LONG(publicKeyBytes.count))
            CC_SHA1_Final(&digest, &ctx)
        }
        let skiValue = Data(digest)
        // extnValue = OCTET STRING { OCTET STRING { sha1Hash } }
        return seq(oid("2.5.29.14") + octetstr(octetstr(skiValue)))
    }

    // MARK: - ASN.1 / DER Primitives

    static func tlv(_ tag: UInt8, _ value: Data) -> Data {
        var out = Data([tag])
        let len = value.count
        if len < 0x80        { out.append(UInt8(len)) }
        else if len < 0x100  { out += [0x81, UInt8(len)] }
        else                  { out += [0x82, UInt8(len >> 8), UInt8(len & 0xFF)] }
        return out + value
    }

    static func seq(_ v: Data)             -> Data { tlv(0x30, v) }
    static func set_(_ v: Data)            -> Data { tlv(0x31, v) }
    static func ctx(_ tag: UInt8, _ v: Data) -> Data { tlv(tag,  v) }
    static func octetstr(_ v: Data)        -> Data { tlv(0x04, v) }
    static func utf8str(_ s: String)       -> Data { tlv(0x0C, Data(s.utf8)) }

    static func bitstring(_ bytes: Data) -> Data {
        tlv(0x03, Data([0x00]) + bytes)   // 0x00 = zero unused bits
    }

    static func integer(_ bytes: [UInt8]) -> Data {
        var b = bytes
        if b.first.map({ $0 & 0x80 != 0 }) ?? false { b.insert(0x00, at: 0) }
        return tlv(0x02, Data(b))
    }

    static func utctime(_ date: Date) -> Data {
        let f = DateFormatter()
        f.dateFormat = "yyMMddHHmmss'Z'"
        f.timeZone = TimeZone(abbreviation: "UTC")
        return tlv(0x17, Data(f.string(from: date).utf8))
    }

    static func oid(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return Data() }
        var body = Data([UInt8(parts[0] * 40 + parts[1])])
        for n in parts.dropFirst(2) { body += base128(n) }
        return tlv(0x06, body)
    }

    private static func base128(_ n: Int) -> [UInt8] {
        var v = n, r = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 { r.insert(UInt8((v & 0x7F) | 0x80), at: 0); v >>= 7 }
        return r
    }
}
