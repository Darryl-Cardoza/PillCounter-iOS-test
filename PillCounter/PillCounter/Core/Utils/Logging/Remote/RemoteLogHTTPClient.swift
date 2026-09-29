import Foundation

enum RemoteLogDeliveryResult: Equatable {
    case delivered
    case retry
    case drop
}

protocol RemoteLogDelivering {
    func deliver(_ body: Data) async -> RemoteLogDeliveryResult
}

/// Isolated from the app's shared network pipeline (BaseRepository/SharedSession)
/// by design — a failure to fetch the auth key or deliver a log must never be
/// logged back through AppLogger, or it creates a feedback loop. Every failure
/// path here is reported as a result after a console-only print.
final class RemoteLogHTTPClient {
    private let session: URLSession
    private let baseURL: () -> String
    private let serverKey: () -> String
    private let accessToken: () -> String

    init(
        session: URLSession? = nil,
        baseURL: @escaping () -> String = { ConfigurationManager.shared.apiBaseURL },
        serverKey: @escaping () -> String = { ConfigurationManager.shared.xServerKey },
        accessToken: @escaping () -> String = { AppStorageManager.shared.accessToken ?? "" }
    ) {
        self.baseURL = baseURL
        self.serverKey = serverKey
        self.accessToken = accessToken
        if let session {
            self.session = session
        } else {
            #if DEBUG
            // Mirrors the app's existing DEBUG SSL-bypass policy (self-signed
            // certs in dev) so log shipping works against the dev backend —
            // but with its own isolated session instance, not the shared one.
            self.session = URLSession(configuration: .ephemeral, delegate: UnsafeSSLManager(), delegateQueue: nil)
            #else
            self.session = URLSession(configuration: .ephemeral)
            #endif
        }
    }

    static func classify(statusCode: Int) -> RemoteLogDeliveryResult {
        switch statusCode {
        case 200..<300: return .delivered
        case 401, 408, 429: return .retry
        case 400..<500: return .drop
        default: return .retry
        }
    }

    func deliver(_ body: Data) async -> RemoteLogDeliveryResult {
        guard let url = URL(string: baseURL() + "/mobile/logs") else {
            #if DEBUG
            print("[RemoteLogHTTPClient] NOT SENT — invalid base URL")
            #endif
            return .retry
        }
        let key = self.serverKey()
        guard !key.isEmpty else {
            #if DEBUG
            print("[RemoteLogHTTPClient] NOT SENT — X-Server-Key is empty")
            #endif
            return .retry
        }

        let token = self.accessToken()
        guard !token.isEmpty else {
            #if DEBUG
            print("[RemoteLogHTTPClient] NOT SENT — no access token")
            #endif
            return .retry
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Server-Key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        do {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .retry }
            #if DEBUG
            print("[RemoteLogHTTPClient] POST \(url.path) → \(http.statusCode) (\(body.count) bytes)")
            if !(200..<300).contains(http.statusCode) {
                print("[RemoteLogHTTPClient] response body: \(String(data: responseData.prefix(500), encoding: .utf8) ?? "<non-UTF8>")")
            }
            #endif
            return Self.classify(statusCode: http.statusCode)
        } catch {
            #if DEBUG
            print("[RemoteLogHTTPClient] delivery failed: \(error)")
            #endif
            return .retry
        }
    }
}

extension RemoteLogHTTPClient: RemoteLogDelivering {}
