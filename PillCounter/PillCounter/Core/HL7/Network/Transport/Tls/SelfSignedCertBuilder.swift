//
//  SelfSignedCertBuilder.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/04/26.
//



import Foundation
import Security
import CryptoKit
import SwiftUI

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
enum SelfSignedCertBuilder {

    enum BuildError: Error {
        case publicKeyExportFailed
        case signingFailed
        case certCreationFailed
    }

    // MARK: - Public API

    /// Creates a DER-encoded self-signed certificate and imports it as SecCertificate.
    /// - Parameters:
    ///   - publicKey:  The EC public key (P-256). Must match `privateKey`.
    ///   - privateKey: The EC private key, may live in Secure Enclave.
    /// - Returns: A `SecCertificate` ready to be stored in the Keychain.
    static func build(publicKey: SecKey, privateKey: SecKey) throws -> SecCertificate {

        // Stable CN tied to this device — keeps the cert the same across rebuilds
        // until the key is rotated.
        let cn = "PillCounter-\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"

        // Export raw EC public key bytes (uncompressed point: 04 || X || Y = 65 bytes)
        var exportError: Unmanaged<CFError>?
        guard let pubKeyData = SecKeyCopyExternalRepresentation(publicKey, &exportError) as Data? else {
            throw BuildError.publicKeyExportFailed
        }

        // Build TBSCertificate (the part that gets signed)
        let tbs = try buildTBS(cn: cn, publicKeyBytes: pubKeyData)

        // Sign TBSCertificate with private key (ES256 = ECDSA-SHA256)
        let signature = try sign(data: tbs, privateKey: privateKey)

        // Wrap into full Certificate ::= SEQUENCE { tbs, signatureAlgorithm, signature }
        let certDER = try wrapCertificate(tbs: tbs, signature: signature)

        guard let cert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw BuildError.certCreationFailed
        }

        return cert
    }

    // MARK: - TBSCertificate

    /// Encodes the TBSCertificate structure (RFC 5280 §4.1).
    private static func buildTBS(cn: String, publicKeyBytes: Data) throws -> Data {

        // version [0] EXPLICIT INTEGER ::= 2  (v3)
        let version = derTagged(tag: 0xA0, value: derInteger(bytes: [0x02]))

        // serialNumber — 8 random bytes keeps it unique per generation
        var serial = Data(count: 8)
        _ = serial.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        let serialNumber = derInteger(bytes: [UInt8](serial))

        // signature AlgorithmIdentifier (ecdsa-with-SHA256)
        let sigAlg = ecdsaSHA256AlgorithmIdentifier()

        // issuer / subject — same DN: CN=<cn>
        let dn = buildDN(cn: cn)

        // validity — now through 10 years
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .year, value: 10, to: now)!
        let validity = derSequence(
            derUTCTime(now) +
            derUTCTime(expiry)
        )

        // subjectPublicKeyInfo — EC P-256
        let spki = buildSPKI(publicKeyBytes: publicKeyBytes)

        // extensions — Basic Constraints (not a CA)
        let basicConstraints = buildBasicConstraintsExtension()
        let extensions = derTagged(tag: 0xA3, value: derSequence(basicConstraints))

        let tbsBody = version + serialNumber + sigAlg + dn + validity + dn + spki + extensions
        return derSequence(tbsBody)
    }

    // MARK: - Full Certificate wrapper

    private static func wrapCertificate(tbs: Data, signature: Data) throws -> Data {
        let sigAlg = ecdsaSHA256AlgorithmIdentifier()

        // signature is a DER BIT STRING — prepend 0x00 (zero unused bits)
        let sigBitString = derBitString(signature)

        let certBody = tbs + sigAlg + sigBitString
        return derSequence(certBody)
    }

    // MARK: - Signing

    private static func sign(data: Data, privateKey: SecKey) throws -> Data {
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw BuildError.signingFailed
        }

        var signError: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(
            privateKey,
            algorithm,
            data as CFData,
            &signError
        ) as Data? else {
            throw BuildError.signingFailed
        }

        return sig
    }

    // MARK: - ASN.1 / DER helpers

    /// SEQUENCE { contents }
    static func derSequence(_ contents: Data) -> Data {
        derTLV(tag: 0x30, value: contents)
    }

    /// INTEGER from raw bytes (prepends 0x00 if high bit set to keep positive)
    static func derInteger(bytes: [UInt8]) -> Data {
        var b = bytes
        if let first = b.first, first & 0x80 != 0 {
            b.insert(0x00, at: 0)   // ensure positive interpretation
        }
        return derTLV(tag: 0x02, value: Data(b))
    }

    /// EXPLICIT context tag wrapper  [n] EXPLICIT
    static func derTagged(tag: UInt8, value: Data) -> Data {
        derTLV(tag: tag, value: value)
    }

    /// BIT STRING (unused-bits byte prepended)
    static func derBitString(_ bytes: Data) -> Data {
        var content = Data([0x00])   // 0 unused bits
        content.append(bytes)
        return derTLV(tag: 0x03, value: content)
    }

    /// UTF8String
    static func derUTF8String(_ s: String) -> Data {
        derTLV(tag: 0x0C, value: Data(s.utf8))
    }

    /// OID from dotted-decimal string
    static func derOID(_ dotted: String) -> Data {
        derTLV(tag: 0x06, value: encodeOID(dotted))
    }

    /// UTCTime — format: YYMMDDHHmmssZ
    static func derUTCTime(_ date: Date) -> Data {
        let f = DateFormatter()
        f.dateFormat = "yyMMddHHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        let str = f.string(from: date) + "Z"
        return derTLV(tag: 0x17, value: Data(str.utf8))
    }

    /// BOOLEAN
    static func derBool(_ v: Bool) -> Data {
        derTLV(tag: 0x01, value: Data([v ? 0xFF : 0x00]))
    }

    /// OCTET STRING
    static func derOctetString(_ bytes: Data) -> Data {
        derTLV(tag: 0x04, value: bytes)
    }

    // MARK: - TLV encoder

    /// Core DER Tag-Length-Value encoder.
    static func derTLV(tag: UInt8, value: Data) -> Data {
        var out = Data()
        out.append(tag)
        let len = value.count
        if len < 0x80 {
            out.append(UInt8(len))
        } else if len < 0x100 {
            out.append(0x81)
            out.append(UInt8(len))
        } else {
            out.append(0x82)
            out.append(UInt8((len >> 8) & 0xFF))
            out.append(UInt8(len & 0xFF))
        }
        out.append(value)
        return out
    }

    // MARK: - OID encoding

    /// Encodes a dotted-decimal OID string into DER bytes.
    private static func encodeOID(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return Data() }

        var bytes = Data()
        bytes.append(UInt8(parts[0] * 40 + parts[1]))

        for i in 2..<parts.count {
            bytes.append(contentsOf: encodeBase128(parts[i]))
        }
        return bytes
    }

    private static func encodeBase128(_ value: Int) -> [UInt8] {
        var v = value
        var result: [UInt8] = []
        result.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            result.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        return result.reversed()
    }

    // MARK: - X.509 structures

    /// AlgorithmIdentifier for ecdsa-with-SHA256 (1.2.840.10045.4.3.2)
    private static func ecdsaSHA256AlgorithmIdentifier() -> Data {
        // ecdsa-with-SHA256 has no parameters field (RFC 5758 §3.2)
        derSequence(derOID("1.2.840.10045.4.3.2"))
    }

    /// SubjectPublicKeyInfo for EC P-256 (id-ecPublicKey + namedCurve prime256v1)
    private static func buildSPKI(publicKeyBytes: Data) -> Data {
        // id-ecPublicKey OID: 1.2.840.10045.2.1
        // prime256v1 OID:     1.2.840.10045.3.1.7
        let algID = derSequence(
            derOID("1.2.840.10045.2.1") +
            derOID("1.2.840.10045.3.1.7")
        )
        let pubKeyBitStr = derBitString(publicKeyBytes)
        return derSequence(algID + pubKeyBitStr)
    }

    /// Distinguished Name: SEQUENCE { SET { SEQUENCE { OID(CN), UTF8String } } }
    private static func buildDN(cn: String) -> Data {
        // commonName OID: 2.5.4.3
        let atv = derSequence(derOID("2.5.4.3") + derUTF8String(cn))
        let rdn = derTLV(tag: 0x31, value: atv)   // SET
        return derSequence(rdn)
    }

    /// BasicConstraints extension: cA = FALSE, critical = FALSE
    private static func buildBasicConstraintsExtension() -> Data {
        // extnID: id-ce-basicConstraints 2.5.29.19
        let oid = derOID("2.5.29.19")
        // extnValue: OCTET STRING wrapping SEQUENCE { BOOLEAN FALSE }
        // cA defaults to FALSE, so an empty SEQUENCE {} is spec-correct and smaller
        let extValue = derOctetString(derSequence(Data()))
        return derSequence(oid + extValue)
    }
}
