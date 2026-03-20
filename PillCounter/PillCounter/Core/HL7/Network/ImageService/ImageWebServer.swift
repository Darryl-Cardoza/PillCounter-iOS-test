//
//  ImageWebServer.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/02/26.
//

import Foundation
import Network

class ImageWebServer {
    
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 8443
    private let queue = DispatchQueue(label: "com.imageserver.network")
    private var connections: [NWConnection] = []
    
    // MARK: - Lifecycle
    
    func start() {
        guard listener == nil else {
            print("Server already running")
            return
        }
        
        do {
            // Configure TLS
            let tlsOptions = try configureTLS()
            let parameters = NWParameters(tls: tlsOptions)
            parameters.allowLocalEndpointReuse = true
            parameters.acceptLocalOnly = false
            
            // Create listener
            listener = try NWListener(using: parameters, on: port)
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("🔐 HTTPS Image Server started")

                    if let ip = currentLANIPAddress() {
                        print("📡 Reachable URLs:")
                        print("   👉 https://\(ip):8443/health")
                        print("   👉 https://\(ip):8443/fingerprint")
                        print("   👉 https://\(ip):8443/images/<filename>")
                    } else {
                        print("⚠️ Could not determine LAN IP")
                    }

                    print("🔑 Cert fingerprint: \(TlsImageKeystoreUtil.shared.getFingerprint())")

                case .failed(let error):
                    print("❌ Server failed:", error)

                case .cancelled:
                    print("🛑 Server cancelled")

                default:
                    break
                }
            }

            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: queue)
            
        } catch {
            print("Failed to start server: \(error)")
        }
    }
    
    func stop() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        print("Server stopped")
    }
    
    // MARK: - TLS Configuration
    
    private func configureTLS() throws -> NWProtocolTLS.Options {
        guard let identity = TlsImageKeystoreUtil.shared.ensureIdentity() else {
            throw NSError(domain: "ImageWebServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get TLS identity"])
        }
        
        let tlsOptions = NWProtocolTLS.Options()
        
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv13)
        
        // Set identity
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, sec_identity_create(identity)!)
        
        return tlsOptions
    }
    
    // MARK: - Connection Handling
    
    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(on: connection)
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.removeConnection(connection)
            case .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }
    
    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                let request = String(data: data, encoding: .utf8) ?? ""
                let response = self.handleHTTPRequest(request)
                self.sendResponse(response, on: connection)
            }
            
            if isComplete {
                connection.cancel()
            } else if error == nil {
                self.receiveRequest(on: connection)
            }
        }
    }
    
    // MARK: - HTTP Request/Response Handling
    
    private func handleHTTPRequest(_ request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return createErrorResponse(code: 400, message: "Bad Request")
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            return createErrorResponse(code: 400, message: "Bad Request")
        }
        
        let method = components[0]
        let path = components[1]
        
        guard method == "GET" else {
            return createErrorResponse(code: 405, message: "Method Not Allowed")
        }
        
        return routeRequest(path: path)
    }
    
    private func routeRequest(path: String) -> String {
        if path == "/health" {
            return handleHealthCheck()
        } else if path == "/fingerprint" {
            return handleFingerprint()
        }else if path.hasPrefix("/image/") {
            let fileName = String(path.dropFirst("/image/".count))
            return handleImageRequest(fileName: fileName)
        }else {
            return createErrorResponse(code: 404, message: "Not Found")
        }
    }
    
    private func handleHealthCheck() -> String {
        let json = """
        {"status":"ok"}
        """
        return createJSONResponse(json: json)
    }
    
    private func handleFingerprint() -> String {
        let fingerprint = TlsImageKeystoreUtil.shared.getFingerprint()
        let json = """
        {"fingerprint":"\(fingerprint)"}
        """
        return createJSONResponse(json: json)
    }
    
    private func handleImageRequest(fileName: String) -> String {
        // Validate filename
        guard isSafeFileName(fileName) else {
            let json = """
            {"success":false,"error":"Invalid file name"}
            """
            return createJSONResponse(json: json, statusCode: 400)
        }
        
        // Find image file
        guard let imageURL = findImageFile(fileName: fileName) else {
            let json = """
            {"success":false,"error":"Image not found"}
            """
            return createJSONResponse(json: json, statusCode: 404)
        }
        
        // Read and encode image
        do {
            let imageData = try Data(contentsOf: imageURL)
            let base64String = imageData.base64EncodedString(options: [.lineLength64Characters])
            // Escape JSON strings properly
            let escapedFileName = fileName.replacingOccurrences(of: "\"", with: "\\\"")
            let json = """
            {"success":true,"file":"\(escapedFileName)","base64":"\(base64String)"}
            """
            return createJSONResponse(json: json)
        } catch {
            let json = """
            {"success":false,"error":"Failed to read image"}
            """
            return createJSONResponse(json: json, statusCode: 500)
        }
    }
    
    // MARK: - Helper Methods
    
    private func findImageFile(fileName: String) -> URL? {
        let fileManager = FileManager.default
        
        let searchRoots = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        
        for root in searchRoots {
            if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent == fileName {
                        return fileURL
                    }
                }
            }
        }
        
        return nil
    }
    
    private func isSafeFileName(_ name: String) -> Bool {
        return !name.isEmpty &&
               !name.contains("..") &&
               !name.contains("/") &&
               !name.contains("\\")
    }
    
    private func createJSONResponse(json: String, statusCode: Int = 200) -> String {
        let statusText = HTTPStatusText(code: statusCode)
        let contentLength = json.utf8.count
        
        return """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(contentLength)\r
        Connection: close\r
        \r
        \(json)
        """
    }
    
    private func createErrorResponse(code: Int, message: String) -> String {
        let json = """
        {"success":false,"error":"\(message)"}
        """
        return createJSONResponse(json: json, statusCode: code)
    }
    
    private func HTTPStatusText(code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
    
    private func sendResponse(_ response: String, on connection: NWConnection) {
        let data = response.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
            connection.cancel()
        })
    }
    
    private func getImageURL(fileName: String) -> URL? {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageDir = baseDir.appendingPathComponent("images") // your folder
        
        let fileURL = imageDir.appendingPathComponent(fileName)
        
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
}


func currentLANIPAddress() -> String? {
    var address: String?

    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return nil }
    defer { freeifaddrs(ifaddr) }

    var ptr = ifaddr
    while ptr != nil {
        let interface = ptr!.pointee
        let addrFamily = interface.ifa_addr.pointee.sa_family

        if addrFamily == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)

            // Wi-Fi + Ethernet (most important)
            if name == "en0" || name == "en1" {
                var addr = interface.ifa_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                getnameinfo(
                    &addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )

                address = String(cString: hostname)
                break
            }
        }
        ptr = interface.ifa_next
    }

    return address
}
