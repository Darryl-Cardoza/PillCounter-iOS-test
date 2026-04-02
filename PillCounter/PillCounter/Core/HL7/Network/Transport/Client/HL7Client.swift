//
//  HL7Client.swift
//  PillCounter
//
//  Created by Bhushan Patil on 05/02/26.
//

import Network
import Foundation

final class HL7TLSClient {

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.pillcounter.hl7.client")

    func connect(host: String, port: Int, onReady: @escaping () -> Void) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
        )

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("HL7 Client connected to \(host):\(port)")
                onReady()
            case .failed(let error):
                print("HL7 Client connection failed: \(error)")
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    func sendHL7(_ hl7: String) {
        guard let connection else { return }

        let framed = MLLP.frame(hl7)

        connection.send(content: framed, completion: .contentProcessed { error in
            if let error {
                print("HL7 send error: \(error)")
            } else {
                print("HL7 message sent")
            }
        })
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }
}


enum MLLP {
    static let start: UInt8 = 0x0B
    static let end1: UInt8 = 0x1C
    static let end2: UInt8 = 0x0D

    static func frame(_ message: String) -> Data {
        var data = Data([start])
        data.append(message.data(using: .utf8)!)
        data.append(contentsOf: [end1, end2])
        return data
    }
}
