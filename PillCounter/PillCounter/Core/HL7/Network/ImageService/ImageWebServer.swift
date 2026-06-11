//
//  ImageWebServer.swift
//  PillCounter
//
//  Fixes applied:
//  1. Route changed from /image/ to /images/ to match C# client URL
//  2. Base64 encoded without line breaks (newlines break C# Convert.FromBase64String)
//


import Foundation
import Network

/// Lightweight HTTPS server serving product images via base64.
final class ImageWebServer {

    private var listener: NWListener?
    private let port: NWEndpoint.Port = 8443
    private let queue = DispatchQueue(label: "com.pillcounter.imageserver", qos: .utility)


    // MARK: - Lifecycle

    /// Starts HTTPS image server. Returns the session token the C# client must use.
    func start() {
        guard listener == nil else { return }

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
            Log("Failed to start image server: \(error.localizedDescription)")
        }

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

        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, sec_identity_create(identity)!)

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

    /// Receives an HTTP request, accumulating bytes until the full header block has
    /// arrived. A single receive() returns as soon as ≥1 byte is available, so under
    /// packet fragmentation it can hand back a PARTIAL request line — which then
    /// routes to 400/404 and the PMS sees an intermittent fetch failure. We are
    /// serving GETs (no body), so the request is complete once we've seen the
    /// "\r\n\r\n" header terminator.
    private func receive(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }

            var buffer = accumulated
            if let data { buffer.append(data) }

            if let error {
                Log("Image server receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            // Headers complete once we see the blank-line terminator.
            let terminator = Data("\r\n\r\n".utf8)
            if buffer.range(of: terminator) != nil {
                guard let request = String(data: buffer, encoding: .utf8) else {
                    self.send(self.errorResponse(400), on: connection)
                    return
                }
                let response = self.handleRequest(request)
                self.send(response, on: connection)
                return
            }

            // Peer closed before sending a full header — give up.
            if isComplete {
                connection.cancel()
                return
            }

            // Guard against an unbounded request from a misbehaving client.
            guard buffer.count <= 65536 else {
                self.send(self.errorResponse(431), on: connection)
                return
            }

            // Need more bytes — keep reading on the same connection.
            self.receive(on: connection, accumulated: buffer)
        }
    }

    // MARK: - Routing

    /// Only endpoint: GET /images/<filename>
    private func handleRequest(_ request: String) -> Data {

        let lines = request.components(separatedBy: "\r\n")

        guard let firstLine = lines.first else {
            return errorResponse(400)
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


    // MARK: - Image Logic

    /// Decrypts the .enc file in-memory and returns a base64 JSON response.
    /// PMS always receives the plain JPEG bytes — the encrypted file is never sent directly.
    private func serveImage(_ fileName: String) -> Data {

        guard isSafe(fileName) else { return errorResponse(400) }

        guard var decrypted = PhotoFileManager.shared.loadDecryptedData(from: fileName) else {
            return errorResponse(404)
        }
        defer { decrypted.resetBytes(in: 0..<decrypted.count) }

        let base64 = decrypted.base64EncodedString(options: [])
        let json = #"{"success":true,"base64":"\#(base64)"}"#
        return httpResponse(json)
    }

    private func isSafe(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("..") && !name.contains("/")
    }

    // MARK: - Response

    /// Builds the full HTTP response as raw bytes. The body (a base64 JPEG) can be
    /// several MB; assembling the header+body as Data and using the exact byte count
    /// for Content-Length avoids a String round-trip and, critically, prevents a
    /// Content-Length / body-length mismatch (interpolating multi-MB base64 into a
    /// Swift String and counting .utf8 separately is fragile) that makes the C#
    /// client read a truncated body and fail the fetch.
    private func httpResponse(_ body: String, status: Int = 200) -> Data {
        let bodyData = Data(body.utf8)
        let header =
            "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(bodyData.count)\r\n" +
            "Connection: close\r\n" +
            "\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        return response
    }

    private static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 431: return "Request Header Fields Too Large"
        default:  return "Error"
        }
    }

    private func errorResponse(_ code: Int) -> Data {
        httpResponse(#"{"success":false}"#, status: code)
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response,
        completion: .contentProcessed { error in
            if let error {
                Log("Image server send error: \(error.localizedDescription)")
            }
            connection.cancel()
        })
    }
}

