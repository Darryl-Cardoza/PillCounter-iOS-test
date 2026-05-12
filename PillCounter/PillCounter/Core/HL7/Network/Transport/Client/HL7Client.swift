//
//  HL7Client.swift
//  PillCounter
//
//  Created by Bhushan Patil on 05/02/26.
//

import Network
import Foundation

/// Handles TCP connection to PMS and sends HL7 messages using MLLP framing.
final class HL7Client {

    /// Active connection to PMS
    private var connection: NWConnection?

    /// Background queue for network operations
    private let queue = DispatchQueue(label: "com.pillcounter.hl7.client")

    /// Establishes connection to PMS using host and port.
    func connect(host: String, port: Int, onReady: @escaping () -> Void) {

        // Configure TCP parameters with peer-to-peer support
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        // Create endpoint from host and port
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
        )

        // Create connection
        connection = NWConnection(to: endpoint, using: parameters)

        // Observe connection state
        connection?.stateUpdateHandler = { state in
            switch state {

            case .ready:
                Log("HL7 Client connected to \(host):\(port)")
                onReady()

            case .failed(let error):
                Log("HL7 Client connection failed: \(error.localizedDescription)")

            default:
                break
            }
        }

        // Start connection
        connection?.start(queue: queue)
    }

    /// Sends HL7 message wrapped in MLLP frame.
    func sendHL7(_ hl7: String) {
        guard let connection else { return }

        let framed = MLLP.frame(hl7)

        connection.send(content: framed, completion: .contentProcessed { error in
            if let error {
                Log("HL7 send error: \(error.localizedDescription)")
            } else {
                Log("HL7 message sent")
            }
        })
    }

    /// Disconnects from PMS.
    func disconnect() {
        connection?.cancel()
        connection = nil
    }
}
