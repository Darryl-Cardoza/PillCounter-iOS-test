//
//  HL7TransportFramer.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/02/26.
//

import Foundation

enum HL7TransportFramer {

    private static let SB: UInt8 = 0x0B   // <VT>
    private static let EB: UInt8 = 0x1C   // <FS>
    private static let CR: UInt8 = 0x0D   // <CR>

    static func wrap(_ message: String) -> Data {
        var data = Data([SB])
        data.append(message.data(using: .utf8)!)
        data.append(contentsOf: [EB, CR])
        return data
    }

    static func unwrap(_ data: Data) -> String? {
        guard
            let start = data.firstIndex(of: SB),
            let end = data.firstIndex(of: EB)
        else { return nil }

        let payload = data[(start + 1)..<end]
        return String(data: payload, encoding: .utf8)
    }
}
