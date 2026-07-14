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
    /// Server-driven (`auth/me` -> `settings.bypass_ssl`, default true): bypass
    /// enabled -> plain HTTP on 8080; disabled -> HTTPS on 8443.
    private var port: NWEndpoint.Port {
        AppStorageManager.shared.bypassSSL ? 8080 : 8443
    }
    private let queue = DispatchQueue(label: "com.pillcounter.imageserver", qos: .utility)


    // MARK: - Lifecycle

    /// Starts the image server, plain HTTP or HTTPS depending on the bypass setting.
    func start() {
        guard listener == nil else { return }

        do {
            let bypassSSL = AppStorageManager.shared.bypassSSL
            let parameters: NWParameters = bypassSSL
                ? .tcp
                : NWParameters(tls: try configureTLS())
            parameters.allowLocalEndpointReuse = true

            let port = self.port
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

    /// Endpoints — mirrors Android's `ImageNanoServer`:
    ///   GET /images/<filename>                                       — single image, base64 JSON
    ///   GET /images/getbymessagecontrolid/<messageControlId>         — zip, by HL7 message control id
    ///   GET /images/getbysequencenumber/<sequenceNumber>             — zip, by HL7 sequence number
    ///   GET /images/getbytransactionorderid/<transactionOrderId>     — zip, by ZUI transaction order id
    ///   GET /images/getbyrxnumber/<rxNumber>/<fillNo>                — zip, exact Rx + fill number
    ///   GET /images/getbyrxnumber/<rxNumber>                         — zip, most recent transaction for Rx
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
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if segments.count == 3, segments[0] == "images", segments[1] == "getbymessagecontrolid" {
            return serveTxnLookup(decode(segments[2])) { TransactionStore.shared.getByMessageControlId($0) }
        }

        if segments.count == 3, segments[0] == "images", segments[1] == "getbysequencenumber" {
            return serveTxnLookup(decode(segments[2])) { TransactionStore.shared.getBySequenceNumber($0) }
        }

        if segments.count == 3, segments[0] == "images", segments[1] == "getbytransactionorderid" {
            return serveTxnLookup(decode(segments[2])) { TransactionStore.shared.getByTransactionOrderId($0) }
        }

        if segments.count == 4, segments[0] == "images", segments[1] == "getbyrxnumber" {
            let rxNumber = decode(segments[2])
            let fillNo = decode(segments[3])
            return serveTxnLookup(rxNumber) { TransactionStore.shared.getByRxNoAndFillNo($0, fillNo: fillNo) }
        }

        if segments.count == 3, segments[0] == "images", segments[1] == "getbyrxnumber" {
            return serveTxnLookup(decode(segments[2])) { TransactionStore.shared.getMostRecentByRxNo($0) }
        }

        guard path.hasPrefix("/images/") else {
            return (errorResponse(404), [])
        }

        return serveImage(String(path.dropFirst("/images/".count)))
    }

    private func decode(_ segment: String) -> String {
        segment.removingPercentEncoding ?? segment
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
        let json = #"{"success":true,"file":"\#(fileName)","base64":"\#(base64)"}"#
        return (httpResponse(json), [fileName])
    }

    private func isSafe(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("..") && !name.contains("/")
    }

    /// One image resolved to bytes, with the naming metadata needed for the zip entry.
    private struct ImageEntry {
        let type: String
        let pillCount: Int32
        let data: Data
        let fileName: String
    }

    /// Looks up a single transaction via `lookup`, collects every image tied to it
    /// (barcode + detail images), and returns the images as a zip. Returns 404 if
    /// the transaction isn't found or has no images.
    private func serveTxnLookup(
        _ key: String,
        lookup: (String) -> PillCountTransactionEntity?
    ) -> (Data, [String]) {
        guard !key.isEmpty, let txn = lookup(key) else { return (errorResponse(404), []) }

        var entries: [ImageEntry] = []
        var deliveredFilenames: [String] = []

        if let barcodeImage = txn.barcode_image, !barcodeImage.isEmpty,
           let data = PhotoFileManager.shared.loadDecryptedData(from: barcodeImage) {
            entries.append(ImageEntry(type: "BARCODE", pillCount: 0, data: data, fileName: barcodeImage))
            deliveredFilenames.append(barcodeImage)
        }

        for detail in TransactionDetailStore.shared.fetchAll(txnId: txn.txn_id) {
            guard let imagePath = detail.image_path, !imagePath.isEmpty,
                  let data = PhotoFileManager.shared.loadDecryptedData(from: imagePath) else { continue }
            entries.append(ImageEntry(type: detail.type ?? "IMAGE", pillCount: detail.pill_count, data: data, fileName: imagePath))
            deliveredFilenames.append(imagePath)
        }

        guard !entries.isEmpty else { return (errorResponse(404), []) }

        return (zipResponse(entries), deliveredFilenames)
    }

    /// Builds a zip whose entries are named `${seq}_rx_${label}_${batchNum}B${batchTotal}_qty${pillCount}.$ext`
    /// — `seq` is the 1-based overall position across all entries, `label` is the
    /// business-meaning image label (`toImageLabel`), `batchNum`/`batchTotal` are
    /// this entry's 1-based position/count within entries sharing that label.
    private func zipResponse(_ entries: [ImageEntry]) -> Data {
        let labels = entries.map { $0.type.toImageLabel }
        let batchTotalsByLabel = Dictionary(grouping: labels, by: { $0 }).mapValues { $0.count }
        var batchCounters: [String: Int] = [:]

        var zip = ZipArchiveWriter()
        for (index, entry) in entries.enumerated() {
            let seq = index + 1
            let label = labels[index]
            let batchNum = (batchCounters[label] ?? 0) + 1
            batchCounters[label] = batchNum
            let batchTotal = batchTotalsByLabel[label] ?? 1
            let ext = (entry.fileName as NSString).pathExtension.isEmpty ? "jpg" : (entry.fileName as NSString).pathExtension
            zip.addEntry(name: "\(seq)_rx_\(label)_\(batchNum)B\(batchTotal)_qty\(entry.pillCount).\(ext)", data: entry.data)
        }

        return zipResponse(zip.finalize(), fileName: "images.zip")
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

