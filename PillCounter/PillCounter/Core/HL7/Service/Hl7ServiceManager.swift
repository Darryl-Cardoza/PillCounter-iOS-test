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
    /// This device's own MLLP listener port — read by the connection-info settings
    /// screen so it can show the PMS side where to dial in.
    let port: UInt16
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

    /// HL7 payload queued by `sendHL7ToPMS` while a reconnect is in flight — flushed
    /// once the client connection reaches `.ready` (see `handleClientStateChange`).
    private var pendingOutboundHL7: String?

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

        startPMSConnection()
    }

    // MARK: - PMS Connection Mode (Bonjour discovery vs server-provided static address)

    /// Server-driven gate (`auth/me` -> `settings.use_static_pms_connection`):
    /// - `false` (Bonjour, default): browse the LAN and connect to the PMS as a client
    ///   first. Only once that connection succeeds — proving the PMS is actually
    ///   reachable — do we start our own TLS + image server (see the `.ready` case in
    ///   `handleClientStateChange`). That server then stays up until `stop()` is called
    ///   or the underlying client connection drops; it does not depend on a live PMS
    ///   client being connected at every instant.
    /// - `true` (static): the server already told us the PMS's exact IP/port, so there's
    ///   nothing to discover or verify — start our server and dial the PMS at the same time.
    private func startPMSConnection() {
        if AppStorageManager.shared.useStaticPMSConnection {
            startServerIfNeeded()
            connectDirectToPMS()
        } else {
            startMonitoringNetwork()
        }
    }

    /// Static mode only: dials the PMS at the server-provided IP/port with no discovery
    /// or reachability check first. Reuses the same TLS/plaintext parameter setup and
    /// `.ready`/`.failed`/`.waiting` state handling as the Bonjour path (`connectToResult`),
    /// just against a fixed endpoint instead of a browse result.
    private func connectDirectToPMS() {
        guard !isConnectingOrConnected else {
            print("[HL7][STATIC] Connect guard hit — already in progress")
            return
        }

        guard
            let host = AppStorageManager.shared.pmsIpAddress, !host.isEmpty,
            let rawPort = AppStorageManager.shared.pmsPort,
            let rawPortU16 = UInt16(exactly: rawPort),
            let pmsPort = NWEndpoint.Port(rawValue: rawPortU16)
        else {
            print("[HL7][STATIC] useStaticPMSConnection is true but pmsIpAddress/pmsPort is missing or invalid — cannot connect")
            return
        }

        print("[HL7][STATIC] Connecting to PMS at \(host):\(pmsPort) — no discovery/verification")
        isConnectingOrConnected = true
        currentServiceName = "\(host):\(pmsPort)"

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: pmsPort)
        let connection = NWConnection(to: endpoint, using: pmsConnectionParameters())
        clientConnection = connection
        connection.stateUpdateHandler = { [weak self] state in self?.handleClientStateChange(state) }
        connection.start(queue: clientQueue)
    }

    /// Shared TLS/plaintext parameter setup for both the Bonjour and static connect
    /// paths — server-driven (`auth/me` -> `settings.bypass_ssl`). Extracted from
    /// `connectToResult` so static mode doesn't duplicate this logic.
    private func pmsConnectionParameters() -> NWParameters {
        Self.makeConnectionParameters()
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

        // Server (TLS + image listener) stays up independent of the outbound client
        // connection — the PMS may dial back in at any time, and dropping the server
        // here would take down the one thing that lets it reconnect.
        if notifyListener { listener?.onClientDisconnected() }

        print("[HL7][CLIENT] Disconnected. Server keeps running.")
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
    /// No-op in static-connect mode — there is no browser to restart.
    func restartBrowsingIfNeeded(pmsServiceType: String) {
        guard !AppStorageManager.shared.useStaticPMSConnection else { return }
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
        currentServiceName = name
        isConnectingOrConnected = true
        print("[HL7][CLIENT] Connecting to PMS service: \(name)")

        let directEndpoint = result.endpoint

        // Server-driven (`auth/me` -> `settings.bypass_ssl`, default true): when
        // enabled, skip TLS entirely and connect over plain TCP. When disabled,
        // negotiate TLS (self-signed PMS cert accepted, as before). Shared with the
        // static-connect path via pmsConnectionParameters().
        let connection = NWConnection(to: directEndpoint, using: pmsConnectionParameters())
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
            AppStorageManager.shared.resolvedPMSServiceName = currentServiceName
            if let path = clientConnection?.currentPath,
               let endpoint = path.remoteEndpoint,
               case let .hostPort(host, port) = endpoint {
                print("[HL7][CLIENT] Resolved endpoint → host: \(host), port: \(port)")
            } else {
                print("[HL7][CLIENT] Resolved endpoint → unavailable (remoteEndpoint nil)")
            }
            listener?.onClientConnected(serviceName: currentServiceName ?? "")
            // Heartbeat disabled — bare MSH\r keepalive was confusing PMS-side parsers.
            // startHeartbeat()
            startReceiving()
            startServerIfNeeded()
            flushPendingOutboundHL7()

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

    /// Sends an MLLP-framed HL7 message to the PMS over the same `clientConnection`
    /// used by both Bonjour and static-IP modes — ACKs flow back through the normal
    /// `startReceiving`/`processReceiveBuffer`/`handleIncomingHL7` pipeline into
    /// `listener?.onAckReceived`, so batch/txn sync-queue retry and ack-tracking apply
    /// identically regardless of connection mode.
    ///
    /// If already connected, sends immediately on the live connection. If not,
    /// queues `hl7` and kicks off a (re)connect via `startPMSConnection()` —
    /// respecting the same static-IP vs Bonjour flag used at launch — then
    /// flushes the queued payload once the connection reaches `.ready`.
    func sendHL7ToPMS(_ hl7: String, orderId: String? = nil) {
        guard isClientConnected, clientConnection != nil else {
            print("[HL7][CLIENT] Not connected — queuing HL7 and reconnecting")
            pendingOutboundHL7 = hl7
            reconnectIfNeeded()
            return
        }
        sendClientHL7(hl7)
    }

    /// Kicks off a (re)connect using the same mode selection as `startPMSConnection()`,
    /// unless one is already in progress. Does NOT re-run `startMonitoringNetwork()`/
    /// re-`start()` the `NWPathMonitor` (already running since init and not safe to
    /// start twice) — instead re-triggers the connect step directly for each mode:
    /// static dials the PMS again, Bonjour re-browses so `connectToResult` fires once
    /// the service reappears.
    private func reconnectIfNeeded() {
        guard !isConnectingOrConnected else {
            print("[HL7][CLIENT] Reconnect already in progress")
            return
        }

        if AppStorageManager.shared.useStaticPMSConnection {
            startServerIfNeeded()
            connectDirectToPMS()
        } else {
            startBrowsing()
        }
    }

    private func flushPendingOutboundHL7() {
        guard let hl7 = pendingOutboundHL7 else { return }
        pendingOutboundHL7 = nil
        print("[HL7][CLIENT] Flushing queued HL7 after reconnect")
        sendClientHL7(hl7)
    }

    /// One-off reachability check for the Settings "Test Connection" button — opens a
    /// connection to the given host/port, reports `.ready`/`.failed`/`.waiting`/timeout,
    /// then cancels. Does not send any HL7 payload and does not touch `clientConnection`
    /// or `isClientConnected` — purely a point-in-time diagnostic.
    enum TestConnectionResult {
        case success
        case failure(String)
    }

    static func testConnection(host: String, port: UInt16, timeout: TimeInterval = 6, completion: @escaping (TestConnectionResult) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(.failure("Invalid port"))
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let connection = NWConnection(to: endpoint, using: Self.makeConnectionParameters())

        var didFinish = false
        func finish(_ result: TestConnectionResult) {
            guard !didFinish else { return }
            didFinish = true
            connection.cancel()
            DispatchQueue.main.async { completion(result) }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(.success)
            case .failed(let error):
                finish(.failure(Self.describeConnectError(error)))
            case .waiting(let error):
                finish(.failure(Self.describeConnectError(error)))
            default:
                break
            }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            finish(.failure("Timed out"))
        }

        connection.start(queue: .global())
    }

    /// Single shared TLS/plaintext parameter builder for every PMS connection path —
    /// Bonjour (`pmsConnectionParameters()`), static-IP, and the Settings "Test
    /// Connection" check. Accepting the peer's cert unconditionally (`completion(true)`)
    /// is intentional: PMS integrations use self-signed certs, so this trades cert
    /// validation for encryption-only TLS. Centralized here so that tradeoff is
    /// visible and changeable in exactly one place.
    private static func makeConnectionParameters() -> NWParameters {
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
        return parameters
    }

    private static func describeConnectError(_ error: NWError) -> String {
        if case .posix(let code) = error {
            switch code {
            case .ECONNREFUSED: return "Connection refused"
            case .ETIMEDOUT: return "Connection timed out"
            case .ECONNRESET: return "Connection reset by peer"
            case .EHOSTUNREACH, .ENETUNREACH: return "Host unreachable"
            default: return "Connection failed (\(code.rawValue))"
            }
        }
        return error.localizedDescription
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
        let frames = MLLP.extractFrames(from: &receiveBuffer)
        for hl7 in frames {
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
