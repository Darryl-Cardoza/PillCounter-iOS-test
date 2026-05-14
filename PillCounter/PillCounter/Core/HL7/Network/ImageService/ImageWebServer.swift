//
//  ImageWebServer.swift
//  PillCounter
//
//  Fixes applied:
//  1. Route changed from /image/ to /images/ to match C# client URL
//  2. Base64 encoded without line breaks (newlines break C# Convert.FromBase64String)
//
//
//  ImageWebServer.swift
//  PillCounter
//
//  Key fixes vs original:
//  1. Route /image/ → /images/  (matches C# client URL)
//  2. TLS: removed verify_block — it was causing the "certificate unknown"
//     fatal alert on the C# side because NWListener's verify_block is a
//     CLIENT certificate verifier. When it fires and calls complete(true)
//     it signals "I verified the client cert" — but if the C# client sends
//     no client cert, the block fires with an empty chain and some TLS
//     stacks interpret this as the server demanding mutual TLS, then
//     send alert 46 (certificate unknown). Removing the block entirely
//     means "client cert is not required" which is correct for our use case.
//  3. Base64: options: []  (no line breaks — C# Convert.FromBase64String
//     throws FormatException on embedded newlines)
//

import Foundation
import Network

/// Lightweight HTTPS server serving product images via base64.
final class ImageWebServer {

    private var listener: NWListener?
    private let port: NWEndpoint.Port = 8443
    private let queue = DispatchQueue(label: "com.pillcounter.imageserver", qos: .utility)

    // MARK: - Session Token
    // Rotated each time the server starts. C# client must send this in X-Api-Key header.
    private(set) var sessionToken: String = ImageWebServer.generateToken()

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Lifecycle

    /// Starts HTTPS image server. Returns the session token the C# client must use.
    @discardableResult
    func start() -> String {
        guard listener == nil else { return sessionToken }
        sessionToken = ImageWebServer.generateToken()

        do {
            let parameters = NWParameters(tls: try configureTLS())
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: port)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Log("Image server running on port \(self.port)")
                case .failed(let error):
                    Log("Image server failed: \(error.localizedDescription)")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.start(queue: queue)
            self.listener = listener

        } catch {
            Log("Failed to start server: \(error.localizedDescription)")
        }

        return sessionToken
    }

    /// Stops server.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - TLS

    /// Configures TLS using bundled certificate.
    private func configureTLS() throws -> NWProtocolTLS.Options {
        guard let identity = TlsImageKeystoreUtil.shared.ensureIdentity() else {
            throw NSError(domain: "TLS", code: -1, userInfo: nil)
        }

        let options = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            options.securityProtocolOptions, .TLSv12
        )

        sec_protocol_options_set_local_identity(
            options.securityProtocolOptions,
            sec_identity_create(identity)!
        )

        return options
    }

    // MARK: - Connection

    /// Handles incoming connection.
    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.receive(on: connection)
            }
        }
        connection.start(queue: queue)
    }

    /// Receives HTTP request.
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, _, _ in

            guard let self, let data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let response = self.handleRequest(request)
            self.send(response, on: connection)
        }
    }

    // MARK: - Routing

    /// Only endpoint: GET /images/<filename>
    private func handleRequest(_ request: String) -> String {

        let lines = request.components(separatedBy: "\r\n")

        guard let firstLine = lines.first else {
            return errorResponse(400)
        }

        // Token check — constant-time comparison to prevent timing attacks
        let providedToken = lines
            .first(where: { $0.lowercased().hasPrefix("x-api-key:") })
            .map { String($0.dropFirst("x-api-key:".count)).trimmingCharacters(in: .whitespaces) }
            ?? ""

        guard constantTimeEqual(providedToken, sessionToken) else {
            return errorResponse(401)
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return errorResponse(405)
        }

        let path = parts[1]

        guard path.hasPrefix("/images/") else {
            return errorResponse(404)
        }

        let fileName = String(path.dropFirst("/images/".count))
        return serveImage(fileName)
    }

    /// Prevents timing-based token guessing by always comparing all bytes.
    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8)
        let bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        return ab.indices.reduce(into: UInt8(0)) { acc, i in acc |= ab[i] ^ bb[i] } == 0
    }

    // MARK: - Image Logic

    /// Decrypts image in-memory and returns base64 JPEG response.
    /// The .enc file is never served raw — PMS always receives plaintext JPEG bytes.
    private func serveImage(_ fileName: String) -> String {

        guard isSafe(fileName) else { return errorResponse(400) }

        guard var decrypted = PhotoFileManager.shared.loadDecryptedData(from: fileName) else {
            return errorResponse(404)
        }
        defer { decrypted.resetBytes(in: 0..<decrypted.count) }

        let base64 = decrypted.base64EncodedString(options: [])
        let json = #"{"success":true,"base64":"\#(base64)"}"#
        return response(json)
    }

    private func isSafe(_ name: String) -> Bool {
        !name.contains("..") && !name.contains("/")
    }

    // MARK: - Response

    private func response(_ body: String, status: Int = 200) -> String {
        return "HTTP/1.1 \(status) OK\r\n" +
               "Content-Type: application/json\r\n" +
               "Content-Length: \(body.utf8.count)\r\n" +
               "\r\n" +
               body
    }

    private func errorResponse(_ code: Int) -> String {
        let body = #"{"success":false}"#
        return response(body, status: code)
    }

    private func send(_ response: String, on connection: NWConnection) {
        connection.send(content: response.data(using: .utf8),
                        completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}



//import Foundation
//import Network
//
//class ImageWebServer {
//
//    private var listener: NWListener?
//    private let port: NWEndpoint.Port = 8443
//    private let queue = DispatchQueue(label: "com.pillcounter.imageserver", qos: .utility)
//    private var connections: [NWConnection] = []
//
//    // MARK: - Lifecycle
//
//    func start() {
//        guard listener == nil else { return }
//
//        do {
//            let tlsOptions = try configureTLS()
//            let parameters = NWParameters(tls: tlsOptions)
//            parameters.allowLocalEndpointReuse = true
//            parameters.acceptLocalOnly = false
//
//            listener = try NWListener(using: parameters, on: port)
//
//            listener?.stateUpdateHandler = { [weak self] state in
//                switch state {
//                case .ready:
//                    print("🔐 HTTPS Image Server started on port 8443")
//                    if let ip = currentLANIPAddress() {
//                        print("📡 https://\(ip):8443/images/<filename>")
//                        print("📡 https://\(ip):8443/health")
//                        print("📡 https://\(ip):8443/fingerprint")
//                    }
//                    print("🔑 \(TlsImageKeystoreUtil.shared.getFingerprint())")
//
//                case .failed(let error):
//                    print("❌ Server failed: \(error)")
//                    // Auto-restart after 3 seconds on transient errors
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                        self?.listener?.cancel()
//                        self?.listener = nil
//                        self?.start()
//                    }
//
//                case .cancelled:
//                    print("🛑 Server cancelled")
//
//                default:
//                    break
//                }
//            }
//
//            listener?.newConnectionHandler = { [weak self] connection in
//                self?.handleConnection(connection)
//            }
//
//            listener?.start(queue: queue)
//
//        } catch {
//            print("❌ Failed to start image server: \(error)")
//        }
//    }
//
//    func stop() {
//        connections.forEach { $0.cancel() }
//        connections.removeAll()
//        listener?.cancel()
//        listener = nil
//    }
//
//    // MARK: - TLS
//
//    private func configureTLS() throws -> NWProtocolTLS.Options {
//        guard let identity = TlsImageKeystoreUtil.shared.ensureIdentity() else {
//            throw NSError(
//                domain: "TLS", code: -1,
//                userInfo: [NSLocalizedDescriptionKey: "No TLS identity — check android-server.p12"]
//            )
//        }
//
//        let options = NWProtocolTLS.Options()
//
//        sec_protocol_options_set_min_tls_protocol_version(
//            options.securityProtocolOptions, .TLSv12
//        )
//
//        sec_protocol_options_set_local_identity(
//            options.securityProtocolOptions,
//            sec_identity_create(identity)!
//        )
//
//        // ✅ DO NOT set a verify_block on a server-side NWProtocolTLS.Options.
//        //
//        // On a server, sec_protocol_options_set_verify_block controls whether
//        // the server demands a client certificate (mutual TLS).
//        // When set, some TLS clients interpret the CertificateRequest message
//        // as mandatory. If they have no client cert to send, they abort with
//        // fatal alert 46 (certificate_unknown) — which is exactly the error
//        // appearing in the logs:
//        //
//        //   boringssl_context_handle_fatal_alert: description: certificate unknown
//        //
//        // Removing the verify_block means: "client cert not required" (one-way TLS).
//        // This is the correct mode for an image HTTP server.
//
//        return options
//    }
//
//    // MARK: - Connection Handling
//
//    private func handleConnection(_ connection: NWConnection) {
//        connections.append(connection)
//
//        connection.stateUpdateHandler = { [weak self] state in
//            switch state {
//            case .ready:
//                self?.receiveRequest(on: connection)
//            case .failed(let error):
//                print("Connection failed: \(error)")
//                self?.removeConnection(connection)
//            case .cancelled:
//                self?.removeConnection(connection)
//            default:
//                break
//            }
//        }
//
//        connection.start(queue: queue)
//    }
//
//    private func removeConnection(_ connection: NWConnection) {
//        connections.removeAll { $0 === connection }
//    }
//
//    private func receiveRequest(on connection: NWConnection) {
//        connection.receive(
//            minimumIncompleteLength: 1,
//            maximumLength: 65_536
//        ) { [weak self] data, _, isComplete, error in
//            guard let self else { return }
//
//            if let data, !data.isEmpty {
//                let request  = String(data: data, encoding: .utf8) ?? ""
//                let response = self.handleHTTPRequest(request)
//                self.sendResponse(response, on: connection)
//            }
//
//            if isComplete {
//                connection.cancel()
//            } else if error == nil {
//                self.receiveRequest(on: connection)
//            }
//        }
//    }
//
//    // MARK: - HTTP Routing
//
//    private func handleHTTPRequest(_ request: String) -> String {
//        let lines = request.components(separatedBy: "\r\n")
//        guard let firstLine = lines.first else {
//            return errorResponse(400, "Bad Request")
//        }
//
//        let parts = firstLine.components(separatedBy: " ")
//        guard parts.count >= 2 else {
//            return errorResponse(400, "Bad Request")
//        }
//
//        guard parts[0] == "GET" else {
//            return errorResponse(405, "Method Not Allowed")
//        }
//
//        return routeRequest(path: parts[1])
//    }
//
//    private func routeRequest(path: String) -> String {
//        switch true {
//        case path == "/health":
//            return jsonResponse(#"{"status":"ok"}"#)
//
//        case path == "/fingerprint":
//            let fp = TlsImageKeystoreUtil.shared.getFingerprint()
//            return jsonResponse(#"{"fingerprint":"\#(fp)"}"#)
//
//        // ✅ FIX 1: /images/ (plural) — matches C# client
//        case path.hasPrefix("/images/"):
//            let fileName = String(path.dropFirst("/images/".count))
//            return handleImageRequest(fileName: fileName)
//
//        default:
//            return errorResponse(404, "Not Found")
//        }
//    }
//
//    // MARK: - Image Handler
//
//    private func handleImageRequest(fileName: String) -> String {
//        guard isSafeFileName(fileName) else {
//            return jsonResponse(#"{"success":false,"error":"Invalid file name"}"#,
//                                status: 400)
//        }
//
//        guard let imageURL = findImageFile(named: fileName) else {
//            return jsonResponse(#"{"success":false,"error":"Image not found: \#(fileName)"}"#,
//                                status: 404)
//        }
//
//        do {
//            let data = try Data(contentsOf: imageURL)
//
//            // ✅ FIX 2: NO line-length option.
//            // C#'s Convert.FromBase64String() throws FormatException on \n inside base64.
//            let base64 = data.base64EncodedString(options: [])
//
//            let safe = fileName.replacingOccurrences(of: "\"", with: "\\\"")
//            return jsonResponse(#"{"success":true,"file":"\#(safe)","base64":"\#(base64)"}"#)
//
//        } catch {
//            return jsonResponse(#"{"success":false,"error":"Failed to read image"}"#,
//                                status: 500)
//        }
//    }
//
//    // MARK: - File Search
//
//    private func findImageFile(named fileName: String) -> URL? {
//        let fm = FileManager.default
//        let roots: [URL] = [
//            fm.urls(for: .documentDirectory,         in: .userDomainMask).first,
//            fm.urls(for: .cachesDirectory,           in: .userDomainMask).first,
//            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
//        ].compactMap { $0 }
//
//        for root in roots {
//            guard let enumerator = fm.enumerator(
//                at: root,
//                includingPropertiesForKeys: [.isRegularFileKey],
//                options: [.skipsHiddenFiles]
//            ) else { continue }
//
//            for case let url as URL in enumerator
//            where url.lastPathComponent == fileName {
//                return url
//            }
//        }
//        return nil
//    }
//
//    private func isSafeFileName(_ name: String) -> Bool {
//        !name.isEmpty && !name.contains("..") &&
//        !name.contains("/") && !name.contains("\\")
//    }
//
//    // MARK: - Response Helpers
//
//    private func jsonResponse(_ json: String, status: Int = 200) -> String {
//        let statusText = httpStatusText(status)
//        let length     = json.utf8.count
//        // Single string — no trailing newline after body to keep Content-Length accurate
//        return "HTTP/1.1 \(status) \(statusText)\r\n" +
//               "Content-Type: application/json\r\n" +
//               "Content-Length: \(length)\r\n" +
//               "Connection: close\r\n" +
//               "\r\n" +
//               json
//    }
//
//    private func errorResponse(_ code: Int, _ message: String) -> String {
//        jsonResponse(#"{"success":false,"error":"\#(message)"}"#, status: code)
//    }
//
//    private func httpStatusText(_ code: Int) -> String {
//        switch code {
//        case 200: "OK"
//        case 400: "Bad Request"
//        case 404: "Not Found"
//        case 405: "Method Not Allowed"
//        case 500: "Internal Server Error"
//        default:  "Unknown"
//        }
//    }
//
//    private func sendResponse(_ response: String, on connection: NWConnection) {
//        guard let data = response.data(using: .utf8) else { return }
//        connection.send(content: data, completion: .contentProcessed { error in
//            if let error { print("Send error: \(error)") }
//            connection.cancel()
//        })
//    }
//}

//// MARK: - LAN IP
//func currentLANIPAddress() -> String? {
//    var address: String?
//    var ifaddr: UnsafeMutablePointer<ifaddrs>?
//    guard getifaddrs(&ifaddr) == 0 else { return nil }
//    defer { freeifaddrs(ifaddr) }
//    var ptr = ifaddr
//    while ptr != nil {
//        let iface = ptr!.pointee
//        if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
//            let name = String(cString: iface.ifa_name)
//            if name == "en0" || name == "en1" {
//                var addr     = iface.ifa_addr.pointee
//                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
//                getnameinfo(&addr, socklen_t(iface.ifa_addr.pointee.sa_len),
//                            &hostname, socklen_t(hostname.count),
//                            nil, 0, NI_NUMERICHOST)
//                address = String(cString: hostname)
//                break
//            }
//        }
//        ptr = iface.ifa_next
//    }
//    return address
//}
