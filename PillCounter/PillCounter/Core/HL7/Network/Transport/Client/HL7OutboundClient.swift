//
//  HL7OutboundClient.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/02/26.
//

import Network
import Foundation

final class HL7OutboundClient {

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "hl7.outbound.queue")

    private(set) var isConnected = false

    init(host: String, port: Int) {
        self.connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
    }

    func connect() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.isConnected = true
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        connection.cancel()
        isConnected = false
    }

    func send(_ message: String) async throws -> String {
        guard isConnected else {
            throw NSError(domain: "HL7OutboundClient",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }

        connection.send(content: HL7TransportFramer.wrap(message),
                        completion: .contentProcessed { _ in })

        return try await receiveAck()
    }

    private func receiveAck() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1,
                               maximumLength: 4096) { data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data,
                          let ack = HL7TransportFramer.unwrap(data) {
                    cont.resume(returning: ack)
                }
            }
        }
    }
}
