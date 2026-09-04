import Foundation
import Network
import Security


/// TLS-enabled HL7 server with Bonjour advertisement and MLLP framing.
final class HL7TLSServer {

    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "hl7.tls.server", qos: .userInitiated)

    // Track every active connection so we can cancel them all on stop().
    // Keyed by ObjectIdentifier so removal is O(1).
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    // Per-connection receive buffer — MLLP frames can arrive split across
    // multiple TCP reads, or several to a read; keyed alongside activeConnections.
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]

    /// Parses/validates a raw HL7 message and returns the ACK/NACK string to
    /// send back, plus the message's control ID (empty if undetermined).
    /// Validation now lives entirely in `Hl7ServiceManager` (via Hl7Core) —
    /// `HL7Server` just frames, forwards, and sends whatever it's given.
    private var onMessage: ((String) -> (ack: String, controlId: String)?)?
    private var onAckSent: ((String) -> Void)?

    init(port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            fatalError("Invalid port \(port)")
        }
        self.port = nwPort
    }

    // MARK: - Start

    func start(
        serviceName: String,
        serviceType: String,
        onMessage: @escaping (String) -> (ack: String, controlId: String)?,
        onAckSent: @escaping (String) -> Void
    ) throws {
        self.onMessage = onMessage
        self.onAckSent = onAckSent

        print("🟡 [HL7][SERVER] start() called — serviceName='\(serviceName)' serviceType='\(serviceType)' port=\(port.rawValue)")

        // Server-driven (`auth/me` -> `settings.bypass_ssl`, default true): when
        // enabled, the MLLP server listens over plain TCP — no TLS handshake.
        let parameters: NWParameters
        if AppStorageManager.shared.bypassSSL {
            parameters = NWParameters.tcp
        } else {
            let tlsOptions = NWProtocolTLS.Options()
            let secIdentity = try TLSIdentityManager.loadOrCreateIdentity()

            guard let osIdentity = sec_identity_create(secIdentity) else {
                print("❌ [HL7][SERVER] sec_identity_create returned nil")
                throw NSError(domain: "TLS", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "sec_identity_create returned nil"])
            }

            sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, osIdentity)
            sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)

            parameters = NWParameters(tls: tlsOptions)
        }
        parameters.allowLocalEndpointReuse = true

        print("🟡 [HL7][SERVER] Creating NWListener on port \(port.rawValue)")
        let listener = try NWListener(using: parameters, on: port)

        listener.service = NWListener.Service(
            name: serviceName,
            type: serviceType,
            domain: "local"
        )
        print("🟡 [HL7][SERVER] Bonjour service set — name='\(serviceName)' type='\(serviceType)'")

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("✅ [HL7][SERVER] NWListener READY — port=\(self?.port.rawValue ?? 0) bonjour='\(serviceName)'")
                Log("HL7 TLS Server ready on port \(self?.port.rawValue ?? 0)")
            case .failed(let error):
                print("❌ [HL7][SERVER] NWListener FAILED — \(error) (posix=\(error.localizedDescription))")
                Log("HL7 TLS Server failed: \(error.localizedDescription)")
                // Attempt recovery — recreate listener after a short delay
                self?.scheduleRestart(serviceName: serviceName, serviceType: serviceType)
            case .cancelled:
                print("🔴 [HL7][SERVER] NWListener CANCELLED")
                Log("HL7 TLS Server stopped")
            case .waiting(let error):
                print("⏳ [HL7][SERVER] NWListener WAITING — \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Log("PMS connected from \(connection.endpoint)")
            self.track(connection)
            self.handle(connection)
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - Stop

    func stop() {
        queue.sync {
            activeConnections.values.forEach { $0.cancel() }
            activeConnections.removeAll()
            listener?.cancel()
            listener = nil
            Log("HL7 TLS Server stopped")
        }
    }
    // MARK: - Connection Tracking

    private func track(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        activeConnections[key] = connection
        Log("HL7 active connections: \(activeConnections.count)")
    }

    private func untrack(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        activeConnections.removeValue(forKey: key)
        receiveBuffers.removeValue(forKey: key)
        Log("HL7 active connections: \(activeConnections.count)")
    }

    // MARK: - Connection Handling

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                Log("HL7 connection ready: \(connection.endpoint)")
                self.receive(on: connection)
            case .failed(let error):
                Log("HL7 connection failed: \(error.localizedDescription)")
                self.untrack(connection)
                connection.cancel()
            case .cancelled:
                self.untrack(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // MARK: - Receive Loop

    /// Recursive receive — keeps reading until the connection closes or errors.
    /// Each call reads one chunk; MLLP framing is handled by the buffer.
    private func receive(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            if let data, !data.isEmpty {
                self.processData(data, on: connection)
            }

            if let error {
                Log("HL7 receive error: \(error.localizedDescription)")
                self.untrack(connection)
                connection.cancel()
                return
            }

            if isComplete {
                Log("HL7 connection closed by remote")
                self.untrack(connection)
                connection.cancel()
                return
            }

            // Connection still open — keep receiving
            self.receive(on: connection)
        }
    }

    // MARK: - MLLP Processing

    private func processData(_ data: Data, on connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        var buffer = receiveBuffers[key] ?? Data()
        buffer.append(data)
        let frames = MLLP.extractFrames(from: &buffer)
        receiveBuffers[key] = buffer

        for hl7 in frames {
            handleFrame(hl7, on: connection)
        }
    }

    private func handleFrame(_ hl7: String, on connection: NWConnection) {
        guard let result = onMessage?(hl7) else { return }

        send(MLLP.frame(result.ack), on: connection) { [weak self] in
            self?.onAckSent?(result.controlId)
        }
    }

    // MARK: - Send Helper

    private func send(_ data: Data, on connection: NWConnection, completion: (() -> Void)? = nil) {
        connection.send(
            content: data,
            completion: .contentProcessed { error in
                if let error {
                    Log("HL7 send error: \(error.localizedDescription)")
                } else {
                    completion?()
                }
            }
        )
    }

    // MARK: - Listener Recovery

    private func scheduleRestart(serviceName: String, serviceType: String) {
        guard let onMessage, let onAckSent else { return }
        listener?.cancel()
        listener = nil
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            do {
                try self.start(
                    serviceName: serviceName,
                    serviceType: serviceType,
                    onMessage: onMessage,
                    onAckSent: onAckSent
                )
                Log("HL7 TLS Server restarted")
            } catch {
                Log("HL7 TLS Server restart failed: \(error.localizedDescription)")
            }
        }
    }
}
