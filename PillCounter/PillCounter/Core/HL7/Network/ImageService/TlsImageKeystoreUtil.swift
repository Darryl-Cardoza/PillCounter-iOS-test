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
    
    private let password = "rite"
    private let alias = "image_https"
    
    private init() {}
    
    // MARK: - Public
    
    func ensureIdentity() -> SecIdentity? {
        if let identity = loadIdentityFromKeychain() {
            print("✅ Loaded identity from keychain")
            return identity
        }
        
        print("⚠️ Identity not found → loading from p12")
        return loadFromP12AndStore()
    }
    
    func getFingerprint() -> String {
        guard let identity = ensureIdentity(),
              let cert = getCertificate(from: identity) else {
            return ""
        }
        
        let data = SecCertificateCopyData(cert) as Data
        return sha256(data)
    }
    
    // MARK: - Keychain
    
    private func loadIdentityFromKeychain() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: alias,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess {
            return item as! SecIdentity
        }
        
        return nil
    }
    
    private func loadFromP12AndStore() -> SecIdentity? {
        guard let url = Bundle.main.url(forResource: "ios-server", withExtension: "p12"),
              let data = try? Data(contentsOf: url) else {
            print("❌ Failed to load p12 file")
            return nil
        }
        
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]
        
        var items: CFArray?
        
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let identityRef = array.first?[kSecImportItemIdentity as String] else {
            print("❌ PKCS12 import failed:", status)
            return nil
        }
        
        let identity = identityRef as! SecIdentity
        
        // 🔥 Store in keychain (important)
        storeIdentity(identity)
        
        return identity
    }
    
    private func storeIdentity(_ identity: SecIdentity) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: alias,
            kSecValueRef as String: identity
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        print("🔐 Store identity status:", status)
    }
    
    // MARK: - Helpers
    
    private func getCertificate(from identity: SecIdentity) -> SecCertificate? {
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        return cert
    }
    
    private func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
