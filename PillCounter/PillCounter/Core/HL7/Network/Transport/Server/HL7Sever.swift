import Foundation
import Network
import Security

/// TLS-enabled HL7 server with Bonjour advertisement and MLLP framing.
final class HL7TLSServer {

    /// Port on which server listens for incoming HL7 connections.
    private let port: NWEndpoint.Port

    /// NWListener for accepting incoming TLS connections.
    private var listener: NWListener?

    /// Background queue for network operations.
    private let queue = DispatchQueue(label: "hl7.tls.server")

    /// Callback for incoming HL7 message.
    private var onMessage: ((String, String) -> Void)?

    /// Callback after ACK is sent.
    private var onAckSent: ((String) -> Void)?

    init(port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            fatalError("Invalid port")
        }
        self.port = nwPort
    }

    // MARK: - Start Server + Bonjour

    /// Starts TLS server and advertises via Bonjour.
    func start(
        serviceName: String,
        serviceType: String,
        onMessage: @escaping (String, String) -> Void,
        onAckSent: @escaping (String) -> Void
    ) throws {

        self.onMessage = onMessage
        self.onAckSent = onAckSent

        // Configure TLS options with local identity
        let tlsOptions = NWProtocolTLS.Options()

        let secIdentity = try TLSIdentityManager.loadOrCreateIdentity()
        guard let osIdentity = sec_identity_create(secIdentity) else {
            throw NSError(domain: "TLS", code: -1, userInfo: nil)
        }

        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            osIdentity
        )

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )

        // Create parameters with TLS
        let parameters = NWParameters(tls: tlsOptions)
        parameters.allowLocalEndpointReuse = true

        // Create listener on port
        let listener = try NWListener(using: parameters, on: port)

        // Advertise service via Bonjour
        listener.service = NWListener.Service(
            name: serviceName,
            type: serviceType,
            domain: "local"
        )

        // Observe server state changes
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Log("HL7 TLS Server ready on port \(self.port)")
            case .failed(let error):
                Log("HL7 TLS Server failed: \(error.localizedDescription)")
            case .cancelled:
                Log("HL7 TLS Server stopped")
            default:
                break
            }
        }

        // Handle incoming client connections
        listener.newConnectionHandler = { connection in
            Log("PMS connected from \(connection.endpoint)")
            self.handle(connection)
        }

        // Start listener
        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - Stop

    /// Stops server and releases resources.
    func stop() {
        listener?.cancel()
        listener = nil
        Log("HL7 TLS Server stopped")
    }

    // MARK: - Connection Handling

    /// Starts handling a new client connection.
    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }

    /// Continuously receives data from connection.
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            data, _, _, error in

            // Process received data
            if let data = data, !data.isEmpty {

                // Extract HL7 message from MLLP frame
                if let hl7 = MLLP.unwrap(data) {

                    let messageId = UUID().uuidString

                    let validation = HL7Validator.validate(hl7)

                    switch validation {

                    case .invalid(let reason):
                        let ack = HL7ACKBuilder.buildResponse(
                            from: hl7,
                            code: .AR,
                            errorMessage: reason
                        )
                        connection.send(content: MLLP.frame(ack), completion: .contentProcessed { _ in })

                    case .unsupported(let reason):
                        let ack = HL7ACKBuilder.buildResponse(
                            from: hl7,
                            code: .AR,
                            errorMessage: reason
                        )
                        connection.send(content: MLLP.frame(ack), completion: .contentProcessed { _ in })

                    case .valid:
                        self.onMessage?(hl7, messageId)
                        let ackMessage = HL7ACKBuilder.buildResponse(
                            from: hl7,
                            code: .AA,
                            errorMessage: nil
                        )
                        connection.send(
                            content: MLLP.frame(ackMessage),
                            completion: .contentProcessed { _ in
                                self.onAckSent?(messageId)
                            }
                        )
                    }
                }
            }

            // Continue receiving if no error
            if error == nil {
                self.receive(on: connection)
            } else {
                Log("Connection error: \(error!.localizedDescription)")
            }
        }
    }
}
