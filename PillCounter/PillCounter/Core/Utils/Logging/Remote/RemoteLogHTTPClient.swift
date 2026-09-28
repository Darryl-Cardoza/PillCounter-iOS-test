import Foundation

protocol RemoteLogSending {
    func send(_ payload: RemoteLogPayload)
}

/// Isolated from the app's shared network pipeline (BaseRepository/SharedSession)
/// by design — a failure to fetch the auth key or deliver a log must never be
/// logged back through AppLogger, or it creates a feedback loop. Every failure
/// path here is swallowed after a console-only print.
final class RemoteLogHTTPClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
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

    func send(_ payload: RemoteLogPayload) {
        guard let url = URL(string: ConfigurationManager.shared.apiBaseURL + "/mobile/logs") else { return }
        let serverKey = ConfigurationManager.shared.xServerKey
        guard !serverKey.isEmpty else { return }
        guard let body = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(serverKey, forHTTPHeaderField: "X-Server-Key")
        request.httpBody = body

        let session = self.session
        Task.detached(priority: .background) {
            do {
                _ = try await session.data(for: request)
            } catch {
                #if DEBUG
                print("[RemoteLogHTTPClient] delivery failed: \(error)")
                #endif
            }
        }
    }
}

extension RemoteLogHTTPClient: RemoteLogSending {}
