//
//  HL7TLSServer.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/02/26.
//

import Foundation
import Network
import Security

final class HL7TLSServer {

    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "hl7.tls.server")

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() throws {

        let tlsOptions = NWProtocolTLS.Options()

        let secIdentity = try TLSIdentityManager.loadIdentity()

        let osIdentity = sec_identity_create(secIdentity)!

        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            osIdentity
        )

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )

        let parameters = NWParameters(tls: tlsOptions)
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: port)

        listener?.stateUpdateHandler = { state in
            if case .ready = state {
                print("✅ HL7 TLS Server listening on \(self.port)")
            }
        }

        listener?.newConnectionHandler = { connection in
            print("🔐 Client connected: \(connection.endpoint)")
            self.handle(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        print("🛑 HL7 TLS Server stopped")
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            data, _, _, error in

            if let data = data, !data.isEmpty {
                let text = String(decoding: data, as: UTF8.self)
                if let hl7 = self.unwrapMLLP(text) {
                    print("📨 HL7:\n\(hl7)")
                    let ack = self.wrapMLLP(self.buildACK())
                    connection.send(content: ack, completion: .contentProcessed { _ in })
                }
            }

            if error == nil {
                self.receive(on: connection)
            }
        }
    }

    // MARK: - MLLP

    private func unwrapMLLP(_ text: String) -> String? {
        let SB = "\u{0B}"
        let EB = "\u{1C}\u{0D}"
        guard let s = text.range(of: SB),
              let e = text.range(of: EB) else { return nil }
        return String(text[s.upperBound..<e.lowerBound])
    }

    private func wrapMLLP(_ msg: String) -> Data {
        ("\u{0B}" + msg + "\u{1C}\u{0D}").data(using: .utf8)!
    }

    private func buildACK() -> String {
        """
        MSH|^~\\&|PillCounter|ROBOT1|PMS|MAINPHARM|\(Date())||ACK^R01|1|P|2.5.1
        MSA|AA|1
        """
    }
}
