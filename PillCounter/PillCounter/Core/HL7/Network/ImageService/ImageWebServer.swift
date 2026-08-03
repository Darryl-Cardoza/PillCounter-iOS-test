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
    /// Plain-HTTP listener on port 80 so PMS can hit the server with a bare IP
    /// (no port in the URL). Runs alongside the primary listener regardless of
    /// bypassSSL — port 80 is always plain HTTP.
    private var portEightyListener: NWListener?
    /// Server-driven (`auth/me` -> `settings.bypass_ssl`, default true): bypass
    /// enabled -> plain HTTP on 8080; disabled -> HTTPS on 8443.
    private var port: NWEndpoint.Port {
        AppStorageManager.shared.bypassSSL ? 8080 : 8443
    }
    private let queue = DispatchQueue(label: "com.pillcounter.imageserver", qos: .utility)


    // MARK: - Lifecycle

    /// Starts the image server, plain HTTP or HTTPS depending on the bypass setting.
    /// Also starts a plain-HTTP listener on port 80 for bare-IP requests (no port in URL).
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

        startPortEighty()
    }

    /// Starts the plain-HTTP port-80 listener (bare-IP, no port in URL).
    private func startPortEighty() {
        guard portEightyListener == nil else { return }

        do {
            let parameters: NWParameters = .tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: 80)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Log("Image server running on port 80")
                case .failed(let error):
                    Log("Image server (port 80) failed: \(error.localizedDescription)")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.start(queue: queue)
            self.portEightyListener = listener

        } catch {
            Log("Failed to start image server on port 80: \(error.localizedDescription)")
        }
    }

    /// Stops server.
    func stop() {
        listener?.cancel()
        listener = nil
        portEightyListener?.cancel()
        portEightyListener = nil
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
    ///   GET /?pic=*&format=zip&orderid=<transactionOrderId>          — zip, PMS root-path format
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

        let rawPath = parts[1]
        let path: String
        let query: [String: String]
        if let queryIndex = rawPath.firstIndex(of: "?") {
            path = String(rawPath[rawPath.startIndex..<queryIndex])
            query = Self.parseQuery(String(rawPath[rawPath.index(after: queryIndex)...]))
        } else if rawPath.contains("=") {
            // PMS sends query params with no leading "?", e.g. "/pic=*&format=zip&orderId=...&Last".
            // Treat everything after the leading "/" as the query string; no separate path segment.
            path = ""
            query = Self.parseQuery(String(rawPath.drop(while: { $0 == "/" })))
        } else {
            path = rawPath
            query = [:]
        }
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // GET /images?pic=*&format=zip&orderid=<transactionOrderId>
        // GET /?pic=*&format=zip&orderid=<transactionOrderId>[&Last]
        // `pic` accepted but ignored for now (future: select which images; "*" = all).
        // `Last` (or any other bare flag) is accepted but ignored.
        if (segments.isEmpty || (segments.count == 1 && segments[0] == "images")),
           query["format"] == "zip", let orderId = query["orderid"], !orderId.isEmpty {
            return serveTxnLookup(orderId, zipFileName: "\(orderId).zip", naming: .pmsFileNaming) { TransactionStore.shared.getByTransactionOrderId($0) }
        }

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

        let crc = ZipArchiveWriter.crc32(ofWholeFile: decrypted)
        let base64 = decrypted.base64EncodedString(options: [])
        let json = #"{"success":true,"file":"\#(fileName)","crc":\#(crc),"base64":"\#(base64)"}"#
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
        let createdAt: Int64
    }

    /// Looks up a single transaction via `lookup`, collects every image tied to it
    /// (barcode + detail images), and returns the images as a zip. Returns 404 if
    /// the transaction isn't found or has no images.
    private func serveTxnLookup(
        _ key: String,
        zipFileName: String = "images.zip",
        naming: ZipNaming = .legacy,
        lookup: (String) -> PillCountTransactionEntity?
    ) -> (Data, [String]) {
        guard !key.isEmpty, let txn = lookup(key) else { return (errorResponse(404), []) }

        var entries: [ImageEntry] = []
        var deliveredFilenames: [String] = []

        let bottleBarcodePaths = [BottleInfo].decode(from: txn.bottle_info_list_json)
            .compactMap { $0.barcodeImagePath }
            .filter { !$0.isEmpty }
        for barcodeImage in bottleBarcodePaths {
            guard let data = PhotoFileManager.shared.loadDecryptedData(from: barcodeImage) else { continue }
            entries.append(ImageEntry(type: "BARCODE", pillCount: 0, data: data, fileName: barcodeImage, createdAt: txn.created_at))
            deliveredFilenames.append(barcodeImage)
        }

        for detail in TransactionDetailStore.shared.fetchAll(txnId: txn.txn_id) {
            guard let imagePath = detail.image_path, !imagePath.isEmpty,
                  let data = PhotoFileManager.shared.loadDecryptedData(from: imagePath) else { continue }
            entries.append(ImageEntry(type: detail.type ?? "IMAGE", pillCount: detail.pill_count, data: data, fileName: imagePath, createdAt: detail.created_at))
            deliveredFilenames.append(imagePath)
        }

        guard !entries.isEmpty else { return (errorResponse(404), []) }

        return (zipResponse(entries, fileName: zipFileName, naming: naming, rxNo: txn.rx_no ?? "", orderId: txn.transaction_order_id ?? ""), deliveredFilenames)
    }

    /// Parses a URL query string (`a=1&b=2`) into a dictionary, percent-decoding
    /// keys and values. Later duplicate keys win.
    private static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let keyValue = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = keyValue.first else { continue }
            let key = (String(rawKey).removingPercentEncoding ?? String(rawKey)).lowercased()
            let rawValue = keyValue.count > 1 ? String(keyValue[1]) : ""
            result[key] = rawValue.removingPercentEncoding ?? rawValue
        }
        return result
    }

    /// Which zip entry naming scheme to use. `.legacy` is the existing
    /// `getby*` route naming (unchanged); `.pmsFileNaming` is the PMS-facing
    /// `Rx_ID_YYYY-MM-DD_HH-MM-SS_TTTT#.jpg` convention (aka Eyecon naming)
    /// used only by the new orderid/query-string endpoint.
    private enum ZipNaming {
        case legacy
        case pmsFileNaming
    }

    /// Maps an internal detail/entry type to its PMS (Eyecon) TTTT code.
    private static func pmsTypeCode(forType type: String) -> String {
        switch type {
        case "scan", "BARCODE":        return "CoVL"
        case "containerInitiate",
             "targetVerification":     return "BWTP"
        case "targetReverification":   return "BWDC"
        case "vial":                   return "CoSS"
        case "containerPending":       return "BWBC"
        default:                       return "BWTP"
        }
    }

    private static let pmsFileNamingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.timeZone = .current
        return formatter
    }()

    /// Builds a zip whose entries are named per `naming`:
    /// `.legacy` — `${seq}_rx_${label}_${batchNum}B${batchTotal}_qty${pillCount}.$ext`
    /// (`seq` = 1-based overall position, `label` = business-meaning image
    /// label via `toImageLabel`, `batchNum`/`batchTotal` = this entry's
    /// 1-based position/count within entries sharing that label).
    /// `.pmsFileNaming` — `Rx_ID_YYYY-MM-DD_HH-MM-SS_TTTT#.jpg` (PMS/Eyecon
    /// naming convention; `TTTT#` = PMS type code + 1-based count per code).
    private func zipResponse(
        _ entries: [ImageEntry],
        fileName: String = "images.zip",
        naming: ZipNaming = .legacy,
        rxNo: String = "",
        orderId: String = ""
    ) -> Data {
        var zip = ZipArchiveWriter()

        switch naming {
        case .legacy:
            let labels = entries.map { $0.type.toImageLabel }
            let batchTotalsByLabel = Dictionary(grouping: labels, by: { $0 }).mapValues { $0.count }
            var batchCounters: [String: Int] = [:]

            for (index, entry) in entries.enumerated() {
                let seq = index + 1
                let label = labels[index]
                let batchNum = (batchCounters[label] ?? 0) + 1
                batchCounters[label] = batchNum
                let batchTotal = batchTotalsByLabel[label] ?? 1
                // `entry.fileName` is the on-disk (encrypted, `.enc`) name — the zip
                // entry holds already-decrypted jpeg bytes, so always name it `.jpg`.
                zip.addEntry(name: "\(seq)_rx_\(label)_\(batchNum)B\(batchTotal)_qty\(entry.pillCount).jpg", data: entry.data)
            }

        case .pmsFileNaming:
            let codes = entries.map { Self.pmsTypeCode(forType: $0.type) }
            var codeCounters: [String: Int] = [:]

            for (index, entry) in entries.enumerated() {
                let code = codes[index]
                let number = (codeCounters[code] ?? 0) + 1
                codeCounters[code] = number
                let date = Date(timeIntervalSince1970: TimeInterval(entry.createdAt) / 1000)
                let timestamp = Self.pmsFileNamingDateFormatter.string(from: date)
                // `entry.fileName` is the on-disk (encrypted, `.enc`) name — the zip
                // entry holds already-decrypted jpeg bytes, so always name it `.jpg`.
                zip.addEntry(name: "\(rxNo)_\(orderId)_\(timestamp)_\(code)\(number).jpg", data: entry.data)
            }
        }

        return zipResponse(zip.finalize(), fileName: fileName)
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
        let crc = ZipArchiveWriter.crc32(ofWholeFile: bodyData)
        let header =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/zip\r\n" +
            "Content-Disposition: attachment; filename=\"\(fileName)\"\r\n" +
            "Content-Length: \(bodyData.count)\r\n" +
            "CRC: \(crc)\r\n" +
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

