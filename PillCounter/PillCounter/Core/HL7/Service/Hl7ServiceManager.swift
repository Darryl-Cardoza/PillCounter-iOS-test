//
//  Hl7ServiceManager.swift
//  PillCounter
//

import Foundation
import ComposeApp
import Network
import Combine

final class Hl7ServiceManager {

    // MARK: - Configuration

    private let port: UInt16
    private let serviceName: String
    private let serviceType: String
    private let pmsServiceType: String

    // MARK: - Server

    private let server: HL7TLSServer
    private let parser = Hl7Parser()
    var imageServer: ImageWebServer?

    // MARK: - Client

    private let discovery = ServiceDiscovery()
    private var clientConnection: NWConnection?
    private let clientQueue = DispatchQueue(label: "com.pillcounter.hl7.client")

    private(set) var isClientConnected = false

    // REQUIRED for streaming ACK parsing
    private var receiveBuffer = Data()

    // MARK: - Events

    weak var listener: Hl7EventListener?

    // MARK: - Init

    init(
        port: UInt16,
        serviceName: String,
        serviceType: String,
        pmsServiceType: String,
        listener: Hl7EventListener
    ) {
        self.port = port
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.pmsServiceType = pmsServiceType
        self.server = HL7TLSServer(port: port)
        self.listener = listener
    }

    // MARK: - Server Lifecycle

    func start() throws {
        print("[HL7][SERVER] Starting HL7 service")

        listener?.onServiceStarted()

        try server.start(
            serviceName: serviceName,
            serviceType: serviceType,
            onMessage: { [weak self] raw, messageId in
                guard let self else { return }
                print("[HL7][SERVER] Message received id=\(messageId)")
                let parsed = self.parser.parse(hl7Message: raw)
                self.listener?.onMessageReceived(
                    message: parsed,
                    messageId: messageId
                )
            },
            onAckSent: { [weak self] messageId in
                print("[HL7][SERVER] ACK sent id=\(messageId)")
                self?.listener?.onAckSent(messageId: messageId)
            }
        )
        imageServer = ImageWebServer()
           imageServer?.start()
        listener?.onServerStarted(port: Int(port))
        listener?.onBonjourRegistered(serviceName: serviceName)

        print("[HL7][SERVER] Started on port \(port)")
    }

    func stop() {
        print("[HL7][SERVER] Stopping")
        server.stop()
        imageServer?.stop()

        listener?.onServiceStopped()
    }

    // MARK: - Client Discovery

    func startClient() {
        print("[HL7][CLIENT] startClient() called")

        discovery.onServiceResolved = { [weak self] host, port, name in
            guard let self else { return }

            print("[HL7][CLIENT] Service resolved name=\(name) host=\(host) port=\(port)")
            self.discovery.stopBrowsing()
            self.connectClient(host: host, port: port)
        }

        print("[HL7][CLIENT] Browsing for service type: \(pmsServiceType)")
        discovery.startBrowsing(serviceType: pmsServiceType)
    }

    func disconnectClient() {
        print("[HL7][CLIENT] Disconnect requested")
        clientConnection?.cancel()
        clientConnection = nil
        isClientConnected = false
        receiveBuffer.removeAll()
        listener?.onClientDisconnected()
    }

    // MARK: - Client Connection

    private func connectClient(host: String, port: Int) {
        print("[HL7][CLIENT] Connecting to \(host):\(port)")

        let tlsOptions = NWProtocolTLS.Options()

        // Enforce TLS 1.2+
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )

        // SNI is REQUIRED
        sec_protocol_options_set_tls_server_name(
            tlsOptions.securityProtocolOptions,
            host
        )

        // TEMP DEV MODE: accept server cert
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completion in
                completion(true)
            },
            DispatchQueue.global()
        )

        let parameters = NWParameters(tls: tlsOptions)
        parameters.includePeerToPeer = true

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
        )

        let connection = NWConnection(to: endpoint, using: parameters)
        self.clientConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            self?.handleClientStateChange(state)
        }

        connection.start(queue: clientQueue)
    }

    private func handleClientStateChange(_ state: NWConnection.State) {
        print("[HL7][CLIENT] State changed -> \(state)")

        switch state {
        case .ready:
            print("[HL7][CLIENT] Connection READY")
            isClientConnected = true
            listener?.onClientConnected()
            startReceiving()

        case .failed(let error):
            print("[HL7][CLIENT] Connection FAILED error=\(error)")
            isClientConnected = false
            listener?.onClientDisconnected()

        case .waiting(let error):
            print("[HL7][CLIENT] Connection WAITING error=\(error)")

        case .cancelled:
            print("[HL7][CLIENT] Connection CANCELLED")
            isClientConnected = false
            listener?.onClientDisconnected()

        default:
            break
        }
    }

    // MARK: - Sending

    func sendClientHL7(_ hl7: String) {
        guard isClientConnected, let connection = clientConnection else {
            print("[HL7][CLIENT] Send skipped (not connected)")
            return
        }

        print("[HL7][CLIENT] Sending HL7 message")
        let framed = MLLP.frame(hl7)

        connection.send(
            content: framed,
            completion: .contentProcessed { error in
                if let error {
                    print("[HL7][CLIENT] Send FAILED error=\(error)")
                } else {
                    print("[HL7][CLIENT] Send SUCCESS")
                }
            }
        )
    }

    // MARK: - Receiving (STREAM SAFE)

    private func startReceiving() {
        print("[HL7][CLIENT] Start receiving")

        clientConnection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                print("[HL7][CLIENT] Receive error=\(error)")
                return
            }

            if let data, !data.isEmpty {
                print("[HL7][CLIENT] Received \(data.count) bytes")
                self.receiveBuffer.append(data)
                self.processReceiveBuffer()
            }

            if !isComplete {
                self.startReceiving()
            }
        }
    }

    // MARK: - MLLP Frame Parsing

    private func processReceiveBuffer() {
        let start: UInt8 = 0x0B
        let end1: UInt8 = 0x1C
        let end2: UInt8 = 0x0D

        while true {
            guard
                let startIndex = receiveBuffer.firstIndex(of: start),
                let endIndex = receiveBuffer.firstIndex(where: { $0 == end1 }),
                endIndex + 1 < receiveBuffer.count,
                receiveBuffer[endIndex + 1] == end2
            else {
                return
            }

            let messageData = receiveBuffer[(startIndex + 1)..<endIndex]
            receiveBuffer.removeSubrange(0...(endIndex + 1))

            guard let hl7 = String(data: messageData, encoding: .utf8) else {
                print("[HL7][CLIENT] Failed to decode HL7 frame")
                continue
            }

            print("[HL7][CLIENT] Complete HL7 frame received")
            handleIncomingHL7(hl7)
        }
    }

    private func handleIncomingHL7(_ hl7: String) {
        print("[HL7][CLIENT] Processing HL7:\n\(hl7)")

        let segments = hl7.components(separatedBy: "\r")
        guard let msa = segments.first(where: { $0.hasPrefix("MSA|") }) else {
            print("[HL7][CLIENT] Not an ACK (no MSA)")
            return
        }

        let fields = msa.components(separatedBy: "|")

        guard fields.count >= 2 else {
            print("[HL7][CLIENT] Invalid MSA segment")
            return
        }

        let ackCode = fields[safe: 1] ?? ""
        let messageIdRaw = fields.count > 2 ? fields[2] : nil
        let messageId = messageIdRaw?.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[HL7][CLIENT] ACK received code=\(ackCode) messageId=\(messageId ?? "nil")")

        listener?.onAckReceived(
            messageId: messageId?.isEmpty == true ? nil : messageId,
            ackCode: ackCode
        )
    }

}
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
