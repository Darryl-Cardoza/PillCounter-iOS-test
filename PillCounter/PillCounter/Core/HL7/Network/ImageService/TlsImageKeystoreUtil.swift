//
//  TlsImageKeystoreUtil.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/02/26.
//

import Foundation
import Security
import CommonCrypto

class TlsImageKeystoreUtil {
    
    static let shared = TlsImageKeystoreUtil()
    
    private let fileName = "android-server.p12"
    private let password = "rite"
    private let alias = "image_https"
    
    private init() {}
    
    // MARK: - Public Methods
    
    func ensureIdentity() -> SecIdentity? {
        if let identity = loadIdentityFromKeychain() {
            return identity
        }
        return createAndStoreIdentity()
    }
    
    func getPassword() -> String {
        return password
    }
    
    func getFingerprint() -> String {
        guard let identity = ensureIdentity(),
              let certificate = getCertificate(from: identity) else {
            return ""
        }
        
        let data = SecCertificateCopyData(certificate) as Data
        return sha256Fingerprint(data: data)
    }
    
    // MARK: - Private Methods
    
    private func loadIdentityFromKeychain() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: alias,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess {
            return (item as! SecIdentity)
        }
        
        return nil
    }
    
    private func createAndStoreIdentity() -> SecIdentity? {
        // Generate RSA key pair
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrIsPermanent as String: false
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &error) else {
            print("Failed to generate key pair: \(String(describing: error))")
            return nil
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            print("Failed to get public key")
            return nil
        }
        
        // Create self-signed certificate
        guard let certificate = createSelfSignedCertificate(publicKey: publicKey, privateKey: privateKey) else {
            print("Failed to create certificate")
            return nil
        }
        
        // Store in keychain
        return storeIdentityInKeychain(certificate: certificate, privateKey: privateKey)
    }
    
    private func createSelfSignedCertificate(publicKey: SecKey, privateKey: SecKey) -> SecCertificate? {
        // Create certificate data
        let subject = "CN=iOSImageServer"
        
        // Get public key data
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            print("Failed to get public key data: \(String(describing: error))")
            return nil
        }
        
        // Create basic X.509 certificate
        let certData = createX509CertificateData(
            publicKeyData: publicKeyData,
            privateKey: privateKey,
            subject: subject
        )
        
        guard let certData = certData else {
            print("Failed to create certificate data")
            return nil
        }
        
        return SecCertificateCreateWithData(nil, certData as CFData)
    }
    
    private func createX509CertificateData(publicKeyData: Data, privateKey: SecKey, subject: String) -> Data? {
        // Create a basic DER-encoded X.509 certificate
        // This is a simplified self-signed certificate
        
        var certificate = Data()
        
        // Certificate version (v3 = 2)
        let version = Data([0xa0, 0x03, 0x02, 0x01, 0x02])
        
        // Serial number
        let serialNumber = Data([0x02, 0x09, 0x00] + Data(count: 8).map { _ in UInt8.random(in: 0...255) })
        
        // Signature algorithm (SHA256withRSA)
        let signatureAlgorithm = Data([
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00
        ])
        
        // Issuer and Subject (CN=iOSImageServer)
        let subjectData = createDistinguishedName(commonName: "iOSImageServer")
        
        // Validity (10 years from now)
        let validity = createValidity(years: 10)
        
        // Public key info
        let publicKeyInfo = createPublicKeyInfo(publicKeyData: publicKeyData)
        
        // Combine all parts
        var tbsCertificate = Data()
        tbsCertificate.append(version)
        tbsCertificate.append(serialNumber)
        tbsCertificate.append(signatureAlgorithm)
        tbsCertificate.append(subjectData) // Issuer
        tbsCertificate.append(validity)
        tbsCertificate.append(subjectData) // Subject
        tbsCertificate.append(publicKeyInfo)
        
        // Wrap in SEQUENCE
        let tbsSequence = wrapInSequence(tbsCertificate)
        
        // Sign the certificate
        guard let signature = signData(tbsSequence, with: privateKey) else {
            return nil
        }
        
        // Final certificate structure
        var finalCert = Data()
        finalCert.append(tbsSequence)
        finalCert.append(signatureAlgorithm)
        finalCert.append(wrapInBitString(signature))
        
        return wrapInSequence(finalCert)
    }
    
    private func createDistinguishedName(commonName: String) -> Data {
        // CN=iOSImageServer in DER format
        var dn = Data()
        
        // SEQUENCE
        var set = Data()
        var sequence = Data()
        
        // OID for CN (2.5.4.3)
        let cnOID = Data([0x06, 0x03, 0x55, 0x04, 0x03])
        
        // UTF8String
        let cnValue = Data([0x0c, UInt8(commonName.count)] + commonName.utf8)
        
        sequence.append(cnOID)
        sequence.append(cnValue)
        
        set.append(wrapInSequence(sequence))
        dn.append(wrapInSet(set))
        
        return wrapInSequence(dn)
    }
    
    private func createValidity(years: Int) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        let notBefore = Date()
        let notAfter = Calendar.current.date(byAdding: .year, value: years, to: notBefore)!
        
        let notBeforeStr = formatter.string(from: notBefore)
        let notAfterStr = formatter.string(from: notAfter)
        
        var validity = Data()
        validity.append(Data([0x17, UInt8(notBeforeStr.count)] + notBeforeStr.utf8))
        validity.append(Data([0x17, UInt8(notAfterStr.count)] + notAfterStr.utf8))
        
        return wrapInSequence(validity)
    }
    
    private func createPublicKeyInfo(publicKeyData: Data) -> Data {
        // RSA OID (1.2.840.113549.1.1.1)
        let rsaOID = Data([
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00
        ])
        
        var pkInfo = Data()
        pkInfo.append(rsaOID)
        pkInfo.append(wrapInBitString(publicKeyData))
        
        return wrapInSequence(pkInfo)
    }
    
    private func signData(_ data: Data, with privateKey: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as Data? else {
            print("Failed to sign data: \(String(describing: error))")
            return nil
        }
        return signature
    }
    
    private func wrapInSequence(_ data: Data) -> Data {
        return wrapWithTag(0x30, data: data)
    }
    
    private func wrapInSet(_ data: Data) -> Data {
        return wrapWithTag(0x31, data: data)
    }
    
    private func wrapInBitString(_ data: Data) -> Data {
        var bitString = Data([0x00]) // No unused bits
        bitString.append(data)
        return wrapWithTag(0x03, data: bitString)
    }
    
    private func wrapWithTag(_ tag: UInt8, data: Data) -> Data {
        var result = Data([tag])
        let length = data.count
        
        if length < 128 {
            result.append(UInt8(length))
        } else if length < 256 {
            result.append(0x81)
            result.append(UInt8(length))
        } else {
            result.append(0x82)
            result.append(UInt8(length >> 8))
            result.append(UInt8(length & 0xFF))
        }
        
        result.append(data)
        return result
    }
    
    private func storeIdentityInKeychain(certificate: SecCertificate, privateKey: SecKey) -> SecIdentity? {
        // Add certificate to keychain
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: alias
        ]
        
        // Delete existing first
        SecItemDelete(certQuery as CFDictionary)
        
        var status = SecItemAdd(certQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to add certificate: \(status)")
        }
        
        // Add private key to keychain
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: privateKey,
            kSecAttrLabel as String: alias,
            kSecAttrApplicationTag as String: alias.data(using: .utf8)!
        ]
        
        SecItemDelete(keyQuery as CFDictionary)
        
        status = SecItemAdd(keyQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to add private key: \(status)")
        }
        
        // Retrieve identity
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: alias,
            kSecReturnRef as String: true
        ]
        
        var identityRef: CFTypeRef?
        status = SecItemCopyMatching(identityQuery as CFDictionary, &identityRef)
        
        if status == errSecSuccess, let identity = identityRef {
            return (identity as! SecIdentity)
        }
        
        print("Failed to retrieve identity: \(status)")
        return nil
    }
    
    private func getCertificate(from identity: SecIdentity) -> SecCertificate? {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        return certificate
    }
    
    private func sha256Fingerprint(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
