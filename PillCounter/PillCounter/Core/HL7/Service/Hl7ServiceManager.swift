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

    private var clientConnection: NWConnection?
    private let clientQueue = DispatchQueue(label: "com.pillcounter.hl7.client")

    private(set) var isClientConnected = false
    private var heartbeatTimer: DispatchSourceTimer?

    // REQUIRED for streaming ACK parsing
    private var receiveBuffer = Data()

    // MARK: - Network / Discovery

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.pillcounter.NetworkMonitor")

    /// Browser is started once on WiFi-up and kept alive until WiFi is lost.
    /// It is NEVER cancelled on PMS disconnect — only on WiFi loss.
    private var browser: NWBrowser?

    /// Prevents duplicate connection attempts while a connection is already
    /// being established or is ready.
    private var isConnectingOrConnected = false

    private var isServerRunning = false

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
        startMonitoringNetwork()
    }

    // MARK: - Service Stop (full teardown)

    func stop() {
        print("[HL7][SERVER] Stopping all services")
        stopBrowsing()
        disconnectClientInternal(notifyListener: true)
        stopServerIfRunning()
        listener?.onServiceStopped()
    }

    // MARK: - Client Disconnect (external call — e.g. from controller)

    func disconnectClient() {
        print("[HL7][CLIENT] External disconnect requested")
        disconnectClientInternal(notifyListener: true)
        // NOTE: browser is intentionally NOT stopped here.
        // It will rediscover PMS automatically.
    }

    // MARK: - Private Client Disconnect

    /// Central method for all client teardown. Browser is never touched here.
    private func disconnectClientInternal(notifyListener: Bool) {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil

        clientConnection?.stateUpdateHandler = nil   // prevent re-entrant callbacks
        clientConnection?.cancel()
        clientConnection = nil

        isClientConnected = false
        isConnectingOrConnected = false
        receiveBuffer.removeAll()

        stopServerIfRunning()

        if notifyListener {
            listener?.onClientDisconnected()
        }

        print("[HL7][CLIENT] Disconnected. Browser keeps running.")
    }

    private func stopServerIfRunning() {
        guard isServerRunning else { return }
        server.stop()
        imageServer?.stop()
        imageServer = nil
        isServerRunning = false
        listener?.onServerStopped()
        print("[HL7][SERVER] Stopped")
    }

    // MARK: - Network Monitoring

    private func startMonitoringNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            if path.status == .satisfied && path.usesInterfaceType(.wifi) {
                print("[HL7][NETWORK] WiFi available — starting browser")
                self.startBrowsing()
            } else {
                print("[HL7][NETWORK] WiFi lost — stopping everything")
                self.stopBrowsing()
                self.disconnectClientInternal(notifyListener: true)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Bonjour Browsing

    /// Starts a permanent NWBrowser. Called only when WiFi becomes available.
    /// Safe to call multiple times — guard prevents duplicate browsers.
    private func startBrowsing() {
        guard browser == nil else {
            print("[HL7][BROWSER] Already running, skipping start")
            return
        }

        print("[HL7][BROWSER] Starting Bonjour browse for '\(pmsServiceType)'")

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let b = NWBrowser(
            for: .bonjour(type: pmsServiceType, domain: nil),
            using: parameters
        )

        b.stateUpdateHandler = { state in
            print("[HL7][BROWSER] State: \(state)")
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            print("[HL7][BROWSER] Results updated count=\(results.count)")

            // If already connected or in-progress, do nothing
            guard !self.isConnectingOrConnected else {
                print("[HL7][BROWSER] Already connected/connecting — skipping")
                return
            }

            // PMS not visible yet — wait for next callback
            guard let result = results.first else {
                print("[HL7][BROWSER] PMS not visible yet — waiting")
                return
            }

            self.connectToResult(result)
        }

        b.start(queue: .main)
        browser = b
    }

    /// Called only when WiFi is lost.
    private func stopBrowsing() {
        guard browser != nil else { return }
        print("[HL7][BROWSER] Stopping browser (WiFi lost)")
        browser?.cancel()
        browser = nil
    }

    // MARK: - Connect to Discovered PMS

    private func connectToResult(_ result: NWBrowser.Result) {
        // Double-check guard — browseResultsChangedHandler can fire rapidly
        guard !isConnectingOrConnected else {
            print("[HL7][CLIENT] Connect guard hit — already in progress")
            return
        }

        guard case let .service(name, _, _, _) = result.endpoint else {
            print("[HL7][CLIENT] Unexpected endpoint type")
            return
        }

        print("[HL7][CLIENT] Connecting to PMS service: \(name)")
        isConnectingOrConnected = true

        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )

        // DEV: accept self-signed cert
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completion in completion(true) },
            DispatchQueue.global()
        )

        let parameters = NWParameters(tls: tlsOptions)
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: result.endpoint, using: parameters)
        clientConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            self?.handleClientStateChange(state)
        }

        connection.start(queue: clientQueue)
    }

    // MARK: - Client State Machine

    private func handleClientStateChange(_ state: NWConnection.State) {
        print("[HL7][CLIENT] State → \(state)")

        switch state {

        case .ready:
            isClientConnected = true
            listener?.onClientConnected()
            startHeartbeat()
            startReceiving()
            startServerIfNeeded()

        case .failed(let error):
            print("[HL7][CLIENT] Failed: \(error)")
            // Clear state, keep browser running
            disconnectClientInternal(notifyListener: true)

        case .waiting(let error):
            // .waiting means Network Framework is retrying internally.
            // We cancel and let the browser rediscover — avoids zombie connections.
            print("[HL7][CLIENT] Waiting (unreachable): \(error) — cancelling")
            disconnectClientInternal(notifyListener: false)

        case .cancelled:
            print("[HL7][CLIENT] Cancelled")
            // Only clear if we weren't already cleared by disconnectClientInternal
            if isConnectingOrConnected {
                disconnectClientInternal(notifyListener: true)
            }

        default:
            break
        }
    }

    // MARK: - Server Startup (after client is ready)

    private func startServerIfNeeded() {
        guard !isServerRunning else {
            print("[HL7][SERVER] Already running")
            return
        }

        do {
            print("[HL7][SERVER] Starting after client verified")

            try server.start(
                serviceName: serviceName,
                serviceType: serviceType,
                onMessage: { [weak self] raw, messageId in
                    guard let self else { return }
                    let parsed = self.parser.parse(hl7Message: raw)
                    self.listener?.onMessageReceived(
                        message: parsed,
                        messageId: messageId
                    )
                },
                onAckSent: { [weak self] messageId in
                    self?.listener?.onAckSent(messageId: messageId)
                }
            )

            imageServer = ImageWebServer()
            imageServer?.start()

            isServerRunning = true

            listener?.onServerStarted(port: Int(port))
            listener?.onBonjourRegistered(serviceName: serviceName)

            print("[HL7][SERVER] Started on port \(port)")

        } catch {
            print("[HL7][SERVER] Failed to start: \(error)")
        }
    }

    // MARK: - Sending

    func sendClientHL7(_ hl7: String) {
        guard isClientConnected, let connection = clientConnection else {
            print("[HL7][CLIENT] Send skipped — not connected")
            return
        }

        print("[HL7][CLIENT] Sending HL7 message")
        let framed = MLLP.frame(hl7)

        connection.send(
            content: framed,
            completion: .contentProcessed { error in
                if let error {
                    print("[HL7][CLIENT] Send FAILED: \(error)")
                } else {
                    print("[HL7][CLIENT] Send SUCCESS")
                }
            }
        )
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: clientQueue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in self?.sendHeartbeat() }
        timer.resume()
        heartbeatTimer = timer

        print("[HL7][CLIENT] Heartbeat started")
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        print("[HL7][CLIENT] Heartbeat stopped")
    }

    private func sendHeartbeat() {
        guard let connection = clientConnection else { return }

        let framed = MLLP.frame("MSH\r")

        connection.send(
            content: framed,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    print("[HL7][CLIENT] Heartbeat FAILED: \(error)")
                    self?.disconnectClientInternal(notifyListener: true)
                } else {
                    print("[HL7][CLIENT] Heartbeat OK")
                }
            }
        )
    }

    // MARK: - Receiving (Stream-safe)

    private func startReceiving() {
        clientConnection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                print("[HL7][CLIENT] Receive error: \(error)")
                return
            }

            if let data, !data.isEmpty {
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
            else { return }

            let messageData = receiveBuffer[(startIndex + 1)..<endIndex]
            receiveBuffer.removeSubrange(0...(endIndex + 1))

            guard let hl7 = String(data: messageData, encoding: .utf8) else {
                print("[HL7][CLIENT] Failed to decode MLLP frame")
                continue
            }

            handleIncomingHL7(hl7)
        }
    }

    private func handleIncomingHL7(_ hl7: String) {
        let segments = hl7.components(separatedBy: "\r")
        guard let msa = segments.first(where: { $0.hasPrefix("MSA|") }) else {
            print("[HL7][CLIENT] Not an ACK (no MSA segment)")
            return
        }

        let fields = msa.components(separatedBy: "|")
        guard fields.count >= 2 else {
            print("[HL7][CLIENT] Invalid MSA segment")
            return
        }

        let ackCode = fields[safe: 1] ?? ""
        let messageId = fields[safe: 2]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("[HL7][CLIENT] ACK received code=\(ackCode) messageId=\(messageId ?? "nil")")

        listener?.onAckReceived(
            messageId: messageId?.isEmpty == true ? nil : messageId,
            ackCode: ackCode
        )
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
