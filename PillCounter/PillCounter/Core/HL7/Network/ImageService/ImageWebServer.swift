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
                let (response, deliveredFilenames) = self.handleRequest(request)
                self.send(response, on: connection) { success in
                    guard success, !deliveredFilenames.isEmpty else { return }
                    ImageDeliveryTracker.shared.markDelivered(deliveredFilenames)
                    for txnId in Self.txnIds(forDeliveredFilenames: deliveredFilenames) {
                        TransactionStore.shared.attemptHardDeleteIfEligible(txnId: txnId)
                    }
                }
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

    /// Endpoints (all nested under /images/):
    ///   GET /images/<filename>                                — single image, base64 JSON
    ///   GET /images/getbyrxnumber/<rxNumber>                   — all images for an Rx, zipped
    ///   GET /images/getbymessagecontrolid/<messageControlId>   — all images for an HL7 message control id, zipped
    private func handleRequest(_ request: String) -> (Data, [String]) {

        let lines = request.components(separatedBy: "\r\n")

        guard let firstLine = lines.first else {
            return (errorResponse(400), [])
        }


        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return (errorResponse(405), [])
        }

        let path = parts[1]

        guard path.hasPrefix("/images/") else {
            return (errorResponse(404), [])
        }

        let subPath = String(path.dropFirst("/images/".count))

        if subPath.hasPrefix("getbyrxnumber/") {
            let rxNumber = String(subPath.dropFirst("getbyrxnumber/".count))
            return serveImagesZip(rxNumber: rxNumber)
        }

        if subPath.hasPrefix("getbymessagecontrolid/") {
            let messageControlId = String(subPath.dropFirst("getbymessagecontrolid/".count))
            return (serveImagesZip(messageControlId: messageControlId), [])
            }

        return serveImage(subPath)
    }


    // MARK: - Image Logic

    /// Decrypts the .enc file in-memory and returns a base64 JSON response.
    /// PMS always receives the plain JPEG bytes — the encrypted file is never sent directly.
    private func serveImage(_ fileName: String) -> (Data, [String]) {

        guard isSafe(fileName) else { return (errorResponse(400), []) }

        guard var decrypted = PhotoFileManager.shared.loadDecryptedData(from: fileName) else {
            return (errorResponse(404), [])
        }
        defer { decrypted.resetBytes(in: 0..<decrypted.count) }

        let base64 = decrypted.base64EncodedString(options: [])
        let json = #"{"success":true,"base64":"\#(base64)"}"#
        return (httpResponse(json), [fileName])
    }

    private func isSafe(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("..") && !name.contains("/")
    }

    /// Builds a zip of every image tied to the given Rx number and returns it as the
    /// HTTP response body. Each entry is named TYPE_SEQ_COUNT.jpg — TYPE is the
    /// detail row's ControlledStep (e.g. TARGET_VERIFICATION), SEQ is its 1-based
    /// occurrence index within that type for this Rx, COUNT is that row's pill_count.
    /// The transaction's own barcode image (if any) is included as BARCODE_SEQ_0.jpg.
    private func serveImagesZip(rxNumber: String) -> (Data, [String]) {
        guard !rxNumber.isEmpty else { return (errorResponse(400), []) }

        let transactions = TransactionStore.shared.fetchByRxNo(rxNumber)
        guard !transactions.isEmpty else { return (errorResponse(404), []) }

        var zip = ZipArchiveWriter()
        var typeSequence: [String: Int] = [:]
        var addedAny = false
        var deliveredFilenames: [String] = []

        for txn in transactions {
            if let barcodeImage = txn.barcode_image, !barcodeImage.isEmpty,
               let data = PhotoFileManager.shared.loadDecryptedData(from: barcodeImage) {
                let seq = nextSequence(for: "BARCODE", in: &typeSequence)
                zip.addEntry(name: "BARCODE_\(seq)_0.jpg", data: data)
                addedAny = true
                deliveredFilenames.append(barcodeImage)
            }

            for detail in TransactionDetailStore.shared.fetchAll(txnId: txn.txn_id) {
                guard let imagePath = detail.image_path, !imagePath.isEmpty,
                      let data = PhotoFileManager.shared.loadDecryptedData(from: imagePath) else { continue }
                let type = detail.type ?? "UNKNOWN"
                let seq = nextSequence(for: type, in: &typeSequence)
                zip.addEntry(name: "\(type)_\(seq)_\(detail.pill_count).jpg", data: data)
                addedAny = true
                deliveredFilenames.append(imagePath)
            }
        }

        guard addedAny else { return (errorResponse(404), []) }

        return (zipResponse(zip.finalize(), fileName: "\(rxNumber).zip"), deliveredFilenames)
    }

    /// HL7 message control ids are not persisted against a transaction today,
    /// so this endpoint has no data to match against and always reports not-found.
    private func serveImagesZip(messageControlId: String) -> Data {
        errorResponse(404)
    }

    /// Resolves which transaction(s) own the given delivered filenames, so a
    /// successful delivery can immediately re-check that transaction for
    /// hard-delete eligibility rather than waiting for the next ACK-driven
    /// check.
    private static func txnIds(forDeliveredFilenames filenames: [String]) -> Set<Int64> {
        var txnIds: Set<Int64> = []
        for filename in filenames {
            if let txnId = TransactionStore.shared.txnId(forBarcodeImage: filename)
                ?? TransactionDetailStore.shared.txnId(forImagePath: filename) {
                txnIds.insert(txnId)
            }
        }
        return txnIds
    }

    private func nextSequence(for type: String, in table: inout [String: Int]) -> Int {
        let next = (table[type] ?? 0) + 1
        table[type] = next
        return next
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

    /// Builds an HTTP response with a binary (zip) body.
    private func zipResponse(_ bodyData: Data, fileName: String) -> Data {
        let header =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/zip\r\n" +
            "Content-Disposition: attachment; filename=\"\(fileName)\"\r\n" +
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

    /// Sends the response and reports via `onComplete` whether every byte was
    /// handed off to the OS network stack with no error. This is the
    /// strongest delivery signal available in this pull-based protocol: it
    /// does not prove the PMS received/parsed the bytes, but it is strictly
    /// stronger than "we built a response" and is what backs image-delivery
    /// tracking for the hard-delete decision.
    private func send(_ response: Data, on connection: NWConnection, onComplete: @escaping (Bool) -> Void = { _ in }) {
        connection.send(content: response,
        completion: .contentProcessed { error in
            if let error {
                Log("Image server send error: \(error.localizedDescription)")
            }
            connection.cancel()
            onComplete(error == nil)
        })
    }
}

