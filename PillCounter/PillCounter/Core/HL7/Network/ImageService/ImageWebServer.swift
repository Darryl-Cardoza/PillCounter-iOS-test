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

    /// Receives HTTP request.
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in

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
    private func serveImage(_ fileName: String) -> String {

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

    private func httpResponse(_ body: String, status: Int = 200) -> String {
         "HTTP/1.1 \(status) OK\r\n" +
         "Content-Type: application/json\r\n" +
         "Content-Length: \(body.utf8.count)\r\n" +
         "\r\n" +
         body
     }

    private func errorResponse(_ code: Int) -> String {
        httpResponse(#"{"success":false}"#, status: code)
    }

    private func send(_ response: String, on connection: NWConnection) {
        connection.send(content: response.data(using: .utf8),
        completion: .contentProcessed { _ in connection.cancel() })
    }
}

