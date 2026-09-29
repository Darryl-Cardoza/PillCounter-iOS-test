//
//  BaseRepositoryProtocol.swift
//  PillCounter
//
//  Created by HC on 05/11/25.
//

import Foundation

// MARK: - Error body decoding
/// Every API response (success or failure) uses the same `{ "message": ... }`
/// envelope shape — decode just that field from an error body so callers can
/// show the server's own text instead of a generic status-code message.
private struct ErrorBody: Decodable { let message: String? }

// MARK: - Shared session storage
private enum SharedSession {
    static let secure: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()
}

protocol BaseRepositoryProtocol {
    static func performRequest<T: Decodable>(
        url: String,
        method: HTTPMethod,
        accessToken: String?,
        body: [String: Any]?,
        responseType: T.Type,
        extraHeaders: [String: String]?
    ) async throws -> T

    static func headers(_ accessToken: String?) -> [String: String]
}

extension BaseRepositoryProtocol {
    static var shouldBypassSSL: Bool { return true }

    // MARK: - Perform Request
    static func performRequest<T: Decodable>(
        url: String,
        method: HTTPMethod,
        accessToken: String? = nil,
        body: [String: Any]? = nil,
        responseType: T.Type,
        extraHeaders: [String: String]? = nil
    ) async throws -> T {
        guard let url = URL(string: url) else {
            logFailure("Invalid request URL", method: method, url: nil)
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        var allHeaders = headers(accessToken)
        allHeaders["Cache-Control"] = "no-store"
        if let extra = extraHeaders?.filter({ !$0.key.isEmpty && !$0.value.isEmpty }) {
            allHeaders.merge(extra) { _, new in new }
        }
        request.allHTTPHeaderFields = allHeaders.filter { !$0.key.isEmpty && !$0.value.isEmpty }

        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                logFailure("Request body serialization failed", method: method, url: url, error: error)
                throw error
            }
        }

        logRequest(request, body: body)

        // SESSION SELECTION
        let session: URLSession
        if shouldBypassSSL {
            #if DEBUG
            session = URLSession(
                configuration: .default,
                delegate: UnsafeSSLManager(),
                delegateQueue: nil
            )
            #else
            session = SharedSession.secure
            #endif
        } else {
            session = SharedSession.secure
        }

        var attempt = 0
        let maxRetries = 2

        while attempt <= maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                logResponse(data, response)

                guard let httpResponse = response as? HTTPURLResponse else {
                    logFailure("Non-HTTP response received", method: method, url: url, attempt: attempt)
                    throw APIError.invalidResponse
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    do {
                        return try JSONDecoder().decode(T.self, from: data)
                    } catch {
                        logFailure("Parsing error for \(T.self)", method: method, url: url,
                                   statusCode: httpResponse.statusCode, attempt: attempt, error: error)
                        throw APIError.parsingError
                    }
                case 401:
                    logFailure("Request unauthorized", method: method, url: url,
                               statusCode: 401, attempt: attempt, isWarning: true, event: .sessionExpired)
                    NotificationCenter.default.post(name: .unauthorizedResponseReceived, object: nil)
                    throw APIError.unauthorized
                case 500 where attempt < maxRetries:
                    logFailure("Server error, retrying", method: method, url: url,
                               statusCode: 500, attempt: attempt, isWarning: true)
                    attempt += 1
                    continue
                default:
                    let code = httpResponse.statusCode
                    let failureMessage = code == 400 ? "Bad request (HTTP 400)"
                        : (400..<500).contains(code) ? "Request rejected (HTTP \(code))"
                        : "Request failed with HTTP \(code)"
                    logFailure(failureMessage, method: method, url: url, statusCode: code, attempt: attempt)
                    // The body may carry a server-authored message (e.g. "Invalid OTP",
                    // "Maximum number of logged-in devices reached...") that's more
                    // useful to show than a generic status-code error — every
                    // non-2xx status (403/404/409/429/5xx/etc.) prefers it when present.
                    if let serverMessage = Self.decodedErrorMessage(from: data) {
                        throw APIError.server(message: serverMessage)
                    }
                    switch httpResponse.statusCode {
                    case 403:
                        throw APIError.forbidden
                    case 404:
                        throw APIError.notFound
                    case 409:
                        throw APIError.conflict
                    case 429:
                        throw APIError.tooManyRequests
                    default:
                        if httpResponse.statusCode >= 500 {
                            NotificationCenter.default.post(name: .serverErrorResponseReceived, object: nil)
                        }
                        throw APIError.serverError(statusCode: httpResponse.statusCode)
                    }
                }

            } catch let error as APIError {
                // A definite HTTP-status error (thrown above) is not transient —
                // retrying it just repeats the same rejected request. Only the
                // network-level catch below (URLSession failure) should retry.
                throw error
            } catch {
                let isTimeout = (error as? URLError)?.code == .timedOut
                if attempt < maxRetries {
                    logFailure("Network failure, retrying", method: method, url: url, attempt: attempt,
                               isWarning: true, event: isTimeout ? .networkTimeout : .networkError, error: error)
                    attempt += 1
                    continue
                } else {
                    logFailure("Network failure", method: method, url: url, attempt: attempt,
                               event: isTimeout ? .networkTimeout : .networkError, error: error)
                    NotificationCenter.default.post(name: .serverErrorResponseReceived, object: nil)
                    throw APIError.unknown(error)
                }
            }
        }

        throw APIError.serverError(statusCode: 500)
    }

    // MARK: - Failure logging
    // Deliberately excludes headers, bodies, query string and the server `message`
    // (it can echo user input) — remote logs must stay free of PII and secrets.
    private static func logFailure(
        _ message: String,
        method: HTTPMethod,
        url: URL?,
        statusCode: Int? = nil,
        attempt: Int? = nil,
        isWarning: Bool = false,
        event: LogEvent = .networkError,
        error: Error? = nil
    ) {
        var context: [String: Any] = ["method": method.rawValue]
        if let path = url?.path { context["path"] = path }
        if let statusCode { context["statusCode"] = statusCode }
        if let attempt { context["attempt"] = attempt }

        if isWarning {
            // warn() has no error parameter, so carry the error in context.
            if let error { context["error"] = String(describing: error) }
            AppLogger.shared.warn(message, event: event, context: context)
        } else {
            AppLogger.shared.error(message, error: error, event: event, context: context)
        }
    }

    // MARK: - Error body decoding
    private static func decodedErrorMessage(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
              let message = body.message, !message.isEmpty else { return nil }
        return message
    }

    // MARK: - Headers
    static func headers(_ accessToken: String?) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept":       "application/json",
        ]

        let serverKey = ConfigurationManager.shared.xServerKey
        if !serverKey.isEmpty {
            headers["X-Server-Key"] = serverKey
        }

        if let token = accessToken, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }

        return headers
    }

    // MARK: - Logging (DEBUG only)
    private static func logRequest(_ request: URLRequest, body: [String: Any]?) {
        #if DEBUG
        print("\n========================= 🌐 API REQUEST =========================")
        print("➡️ URL: \(request.url?.absoluteString ?? "nil")")
        print("➡️ Method: \(request.httpMethod ?? "nil")")

        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            print("➡️ Headers:")
            headers.forEach { key, value in
                let redacted = ["X-Server-Key", "Authorization"]
                let display = redacted.contains(key) ? String(repeating: "*", count: 8) : value
                print("   \(key): \(display)")
            }
        }

        if let body = body,
           let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("➡️ Body:\n\(jsonString)")
        } else if request.httpBody != nil {
            print("➡️ Body: [Binary or Encoded Data]")
        } else {
            print("➡️ Body: None")
        }

        print("==================================================================\n")
        #endif
    }

    private static func logResponse(_ data: Data, _ response: URLResponse?) {
        #if DEBUG
        print("\n========================= 📩 API RESPONSE =========================")
        if let httpResponse = response as? HTTPURLResponse {
            print("⬅️ Status Code: \(httpResponse.statusCode)")
            print("⬅️ URL: \(httpResponse.url?.absoluteString ?? "nil")")
        }

        if let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let jsonString = String(data: prettyData, encoding: .utf8) {
            print("⬅️ Response Body:\n\(jsonString)")
        } else if !data.isEmpty {
            print("⬅️ Response Body: [Non-JSON Data, \(data.count) bytes]")
        } else {
            print("⬅️ Response Body: Empty")
        }

        print("==================================================================\n")
        #endif
    }
}

// MARK: - SSL Bypass Delegate (Development Only)
#if DEBUG
class UnsafeSSLManager: NSObject, URLSessionDelegate, URLSessionTaskDelegate {

    // Session-level challenge (connection-level TLS).
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    // Task-level challenge — consulted by the async/task-based `data(for:)` API.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            print("🔓 SSL: non-server-trust challenge (\(challenge.protectionSpace.authenticationMethod)) → default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        print("🔓 SSL: bypassing server trust for \(challenge.protectionSpace.host)")
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
#endif
