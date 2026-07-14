//
//  Hl7ServiceManager.swift
//  PillCounter
//

import Foundation
import Hl7Core
import Network
import Combine


final class Hl7ServiceManager {

    // MARK: - Configuration
    private let port: UInt16
    private let serviceName: String
    private let serviceType: String
    private var pmsServiceType: String

    // MARK: - Server
    private let server: HL7TLSServer

    /// `HL7` is the batteries-included entry point of the new Hl7Core library: it owns
    /// parsing (`parse(raw:)`), building (`build()`), validation (`validate(message:)`)
    /// and ACK generation (`ack(message:)`) for a given HL7 version.
    ///
    /// Parameters:
    /// - `version`: HL7 version this PMS integration speaks (e.g. "2.3"). Governs which
    ///   fields/segments are considered valid and how messages are re-encoded.
    /// - `strictMode`: When `true`, parsing throws on any structural error instead of
    ///   collecting them into `HL7ParseResult.Failure`. Kept `false` so a malformed
    ///   segment from the PMS doesn't take down the whole receive pipeline — we still get
    ///   a `partialMessage` plus the list of `errors` to log/ACK against.
    /// - `validationConfig`: Rule set used by `validate(message:)`/`ack(message:)` to decide
    ///   AA vs AE/AR. `.DEFAULT` applies the library's standard structural HL7 rules with no
    ///   pharmacy-specific overrides.
    /// - `extraSegments`: Registers additional custom (Z-)segment types so they parse as
    ///   typed views instead of falling back to a generic/lossless segment. Left empty
    ///   because every custom segment this app sends/receives — ZIN (inventory: opened/
    ///   sealed quantity, lot, expiry) and ZPR (Rx priority) — is already pre-registered by
    ///   the library itself.
    private let hl7 = HL7(
        version: AppStorageManager.shared.hl7Version,
        strictMode: false,	
        validationConfig: .companion.DEFAULT,
        extraSegments: []
    )

    var imageServer: ImageWebServer?

    // MARK: - Client
    private var clientConnection: NWConnection?
    private let clientQueue = DispatchQueue(label: "com.pillcounter.hl7.client")

    private(set) var isClientConnected = false
    private var heartbeatTimer: DispatchSourceTimer?
    private var receiveBuffer = Data()

    // MARK: - Network / Discovery
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.pillcounter.NetworkMonitor")

    private var browser: NWBrowser?
    private var isConnectingOrConnected = false
    private var isServerRunning = false
    private var currentInterface: NWInterface?
    private var currentServiceName: String?

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
        self.port           = port
        self.serviceName    = serviceName
        self.serviceType    = serviceType
        self.pmsServiceType = pmsServiceType
        self.server         = HL7TLSServer(port: port)
        self.listener       = listener
        startMonitoringNetwork()
    }

    // MARK: - Stop

    func stop() {
        print("[HL7][SERVER] Stopping all services")
        stopBrowsing()
        disconnectClientInternal(notifyListener: true)
        stopServerIfRunning()
    }

    func disconnectClient() {
        print("[HL7][CLIENT] External disconnect requested")
        disconnectClientInternal(notifyListener: true)
    }

    private func disconnectClientInternal(notifyListener: Bool) {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil

        clientConnection?.stateUpdateHandler = nil
        clientConnection?.cancel()
        clientConnection = nil

        isClientConnected       = false
        isConnectingOrConnected = false
        receiveBuffer.removeAll()

        stopServerIfRunning()

        if notifyListener { listener?.onClientDisconnected() }

        print("[HL7][CLIENT] Disconnected. Browser keeps running.")
    }

    private func stopServerIfRunning() {
        guard isServerRunning else { return }
        server.stop()
        imageServer?.stop()
        imageServer    = nil
        isServerRunning = false
        print("[HL7][SERVER] Stopped")
    }

    // MARK: - Network Monitoring

    private func startMonitoringNetwork() {
        print("🟡 [HL7][NETWORK] startMonitoringNetwork() called — serviceName='\(serviceName)'")
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            print("🌐 [HL7][NETWORK] path update — status=\(path.status) wifi=\(path.usesInterfaceType(.wifi)) cellular=\(path.usesInterfaceType(.cellular))")

            if path.status == .satisfied && path.usesInterfaceType(.wifi) {
                let activeInterface = path.availableInterfaces.first(where: { $0.type == .wifi })

                if activeInterface?.name != self.currentInterface?.name {
                    print("[HL7][NETWORK] WiFi interface changed → restarting browser")
                    self.currentInterface = activeInterface
                    self.stopBrowsing()
                    self.disconnectClientInternal(notifyListener: true)
                }

                self.startBrowsing()
            } else {
                print("[HL7][NETWORK] WiFi lost — stopping everything")
                self.currentInterface = nil
                self.stopBrowsing()
                self.disconnectClientInternal(notifyListener: true)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Bonjour Browsing

    private func startBrowsing() {
        // FIX: Do not start the browser if pmsServiceType is empty.
        // NWBrowser passes the type directly to DNSServiceBrowse, which
        // returns BadParam(-65540) for an empty string, triggering an
        // infinite restart loop (failed → restart in 3s → failed → ...).
        guard !pmsServiceType.isEmpty else {
            print("[HL7][BROWSER] pmsServiceType is empty — browse skipped until settings load")
            return
        }

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

        b.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            print("[HL7][BROWSER] State: \(state)")

            if case .failed(let error) = state {
                // BadParam means the service type is invalid — no point retrying.
                // Any other error is transient; restart after a short delay.
                let nsError = error as NSError
                let isBadParam = nsError.code == -65540
                if isBadParam {
                    print("[HL7][BROWSER] BadParam — invalid service type '\(self.pmsServiceType)', not retrying")
                    self.browser?.cancel()
                    self.browser = nil
                    return
                }

                print("[HL7][BROWSER] Failed: \(error) — restarting in 3s")
                self.browser?.cancel()
                self.browser = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self else { return }
                    guard self.monitor.currentPath.status == .satisfied,
                          self.monitor.currentPath.usesInterfaceType(.wifi) else { return }
                    self.startBrowsing()
                }
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            print("[HL7][BROWSER] Results updated count=\(results.count)")

            guard !self.isConnectingOrConnected else {
                print("[HL7][BROWSER] Already connected/connecting — skipping")
                return
            }

            guard let result = results.first else {
                print("[HL7][BROWSER] PMS not visible yet — waiting")
                return
            }

            self.connectToResult(result)
        }

        b.start(queue: .main)
        browser = b
    }

    private func stopBrowsing() {
        guard browser != nil else { return }
        print("[HL7][BROWSER] Stopping browser (WiFi lost)")
        browser?.cancel()
        browser = nil
    }

    // MARK: - Restart browsing (called by Hl7ServiceController after settings load)

    /// Call this after mobile settings have been fetched and pmsHostName is populated.
    /// Updates the stored service type and starts (or restarts) the Bonjour browser.
    func restartBrowsingIfNeeded(pmsServiceType: String) {
        guard !pmsServiceType.isEmpty else { return }
        self.pmsServiceType = pmsServiceType
        stopBrowsing()
        startBrowsing()
    }

    // MARK: - Connect to Discovered PMS

    private func connectToResult(_ result: NWBrowser.Result) {
        guard !isConnectingOrConnected else {
            print("[HL7][CLIENT] Connect guard hit — already in progress")
            return
        }

        guard case let .service(name, _, _, _) = result.endpoint else { return }
        currentServiceName      = name
        isConnectingOrConnected = true
        print("[HL7][CLIENT] Connecting to PMS service: \(name)")

        // Server-driven (`auth/me` -> `settings.bypass_ssl`, default true): when
        // enabled, skip TLS entirely and connect over plain TCP. When disabled,
        // negotiate TLS (self-signed PMS cert accepted, as before).
        let parameters: NWParameters
        if AppStorageManager.shared.bypassSSL {
            parameters = NWParameters.tcp
        } else {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(
                tlsOptions.securityProtocolOptions, .TLSv12
            )
            sec_protocol_options_set_verify_block(
                tlsOptions.securityProtocolOptions,
                { _, _, completion in completion(true) },
                DispatchQueue.global()
            )
            parameters = NWParameters(tls: tlsOptions)
        }
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: result.endpoint, using: parameters)
        clientConnection = connection
        connection.stateUpdateHandler = { [weak self] state in self?.handleClientStateChange(state) }
        connection.start(queue: clientQueue)
    }

    // MARK: - Client State Machine

    private func handleClientStateChange(_ state: NWConnection.State) {
        print("[HL7][CLIENT] State → \(state)")

        switch state {
        case .ready:
            isClientConnected = true
            listener?.onClientConnected(serviceName: currentServiceName ?? "")
            startHeartbeat()
            startReceiving()
            startServerIfNeeded()

        case .failed(let error):
            print("[HL7][CLIENT] Failed: \(error)")
            disconnectClientInternal(notifyListener: true)

        case .waiting(let error):
            print("[HL7][CLIENT] Waiting (unreachable): \(error) — cancelling")
            disconnectClientInternal(notifyListener: false)

        case .cancelled:
            print("[HL7][CLIENT] Cancelled")
            if isConnectingOrConnected { disconnectClientInternal(notifyListener: true) }

        default:
            break
        }
    }

    // MARK: - Server Startup

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
                    print("Raw message -> \(raw)")

                    let result = self.hl7.parse(raw: raw)
                    guard let success = result as? HL7ParseResult.Success else {
                        let failure = result as? HL7ParseResult.Failure
                        let reasons = failure?.errors.map { $0.message }.joined(separator: "; ") ?? "unknown parse failure"
                        print("[HL7][SERVER] Failed to parse incoming message: \(reasons)")
                        self.listener?.onError(source: "Hl7ServiceManager.parse", error: Hl7ParseFailureError(reason: reasons))
                        return
                    }

                    self.listener?.onMessageReceived(
                        message: success.message,
                        rawHl7: raw
                    )
                },
                onAckSent: { [weak self] messageId in
                    self?.listener?.onAckSent(messageId: messageId)
                }
            )

            imageServer = ImageWebServer()
            imageServer?.start()
            isServerRunning = true

            listener?.onBonjourRegistered(serviceName: serviceName)
            print("[HL7][SERVER] Started on port \(port)")

        } catch {
            print("[HL7][SERVER] Failed to start: \(error)")
        }
    }

    // MARK: - Sending

    /// Sends an MLLP-framed HL7 message to the connected PMS.
    /// - Returns: `true` if the message was handed to the connection for sending,
    ///   `false` if there is no live connection (caller must NOT treat it as in-flight).
    @discardableResult
    func sendClientHL7(_ hl7: String) -> Bool {
        guard isClientConnected, let connection = clientConnection else {
            print("[HL7][CLIENT] Send skipped — not connected")
            return false
        }

        let framed = MLLP.frame(hl7)
        connection.send(content: framed, completion: .contentProcessed { error in
            if let error { print("[HL7][CLIENT] Send FAILED: \(error)") }
            else         { print("[HL7][CLIENT] Send SUCCESS") }
        })
        return true
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

    private func sendHeartbeat() {
        guard let connection = clientConnection else { return }
        connection.send(
            content: MLLP.frame("MSH\r"),
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

    // MARK: - Receiving

    private func startReceiving() {
        clientConnection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error { print("[HL7][CLIENT] Receive error: \(error)"); return }

            if let data, !data.isEmpty {
                receiveBuffer.append(data)
                processReceiveBuffer()
            }

            if !isComplete { startReceiving() }
        }
    }

    private func processReceiveBuffer() {
        let start: UInt8 = 0x0B
        let end1:  UInt8 = 0x1C
        let end2:  UInt8 = 0x0D

        while true {
            guard
                let startIndex = receiveBuffer.firstIndex(of: start),
                let endIndex   = receiveBuffer.firstIndex(where: { $0 == end1 }),
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

        let fields  = msa.components(separatedBy: "|")
        guard fields.count >= 2 else { print("[HL7][CLIENT] Invalid MSA"); return }

        let ackCode   = fields[safe: 1] ?? ""
        let messageId = fields[safe: 2]?.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[HL7][CLIENT] ACK received code=\(ackCode) messageId=\(messageId ?? "nil")")

        listener?.onAckReceived(
            messageId: messageId?.isEmpty == true ? nil : messageId,
            ackCode: ackCode,
            hl7: hl7
        )
    }

}
