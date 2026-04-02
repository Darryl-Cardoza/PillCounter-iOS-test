//
//  TLSIdentityManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/02/26.
//

import Foundation
import Security

final class TLSIdentityManager {

    static func loadIdentity() throws -> SecIdentity {

        guard let url = Bundle.main.url(forResource: "android-server", withExtension: "p12"),
              let data = try? Data(contentsOf: url) else {
            throw NSError(domain: "TLS", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "android-server not found"
            ])
        }

        let options: [String: Any] = [
            kSecImportExportPassphrase as String: "rite"
        ]

        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess else {
            throw NSError(domain: "TLS", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to import PKCS#12: status \(status)"])
        }

        guard let itemsArray = items as? [[String: Any]], let firstItem = itemsArray.first else {
            throw NSError(domain: "TLS", code: -2, userInfo: [NSLocalizedDescriptionKey: "PKCS#12 import returned no items"])
        }

        guard let identityAny = firstItem[kSecImportItemIdentity as String] else {
            throw NSError(domain: "TLS", code: -3, userInfo: [NSLocalizedDescriptionKey: "No identity found in PKCS#12 import result"])
        }

        let identity = identityAny as! SecIdentity
        return identity
    }
}

