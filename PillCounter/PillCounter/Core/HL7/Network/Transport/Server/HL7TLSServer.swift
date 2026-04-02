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

    private var onMessage: ((String, String) -> Void)?
    private var onAckSent: ((String) -> Void)?

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    // MARK: - Start Server + Bonjour

    func start(
        serviceName: String,
        serviceType: String,
        onMessage: @escaping (String, String) -> Void,
        onAckSent: @escaping (String) -> Void
    ) throws {

        self.onMessage = onMessage
        self.onAckSent = onAckSent

        // TLS configuration
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

        let listener = try NWListener(using: parameters, on: port)

        // Advertise THIS listener via Bonjour
        listener.service = NWListener.Service(
            name: serviceName,
            type: serviceType,   // e.g. "_hl7._tcp"
            domain: "local"
        )

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("HL7 TLS Server + Bonjour ready on port \(self.port)")
            case .failed(let error):
                print(" HL7 TLS Server failed: \(error)")
            case .cancelled:
                print("HL7 TLS Server cancelled")
            default:
                break
            }
        }

        listener.newConnectionHandler = { connection in
            print(" PMS connected from \(connection.endpoint)")
            self.handle(connection)
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - Stop

    func stop() {
        listener?.cancel()
        listener = nil
        print("HL7 TLS Server stopped")
    }

    // MARK: - Connection Handling

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
                    let messageId = UUID().uuidString

                    print("HL7 received:\n\(hl7)")
                    self.onMessage?(hl7, messageId)

                    let ack = self.wrapMLLP(self.buildACK())
                    connection.send(content: ack, completion: .contentProcessed { _ in
                        self.onAckSent?(messageId)
                    })
                }
            }

            if error == nil {
                self.receive(on: connection)
            } else {
                print(" Connection error: \(error!)")
            }
        }
    }

    // MARK: - MLLP Helpers

    private func unwrapMLLP(_ text: String) -> String? {
        let SB = "\u{0B}"
        let EB = "\u{1C}\u{0D}"
        guard let s = text.range(of: SB),
              let e = text.range(of: EB) else { return nil }
        return String(text[s.upperBound..<e.lowerBound])
    }

    private func wrapMLLP(_ msg: String) -> Data {
        ("\u{0B}" + msg + "\u{1C}\u{0D}")
            .data(using: .utf8)!
    }

    private func buildACK() -> String {
        """
        MSH|^~\\&|PillCounter|ROBOT1|PMS|MAINPHARM|\(Date())||ACK^R01|1|P|2.5.1
        MSA|AA|1
        """
    }
}
