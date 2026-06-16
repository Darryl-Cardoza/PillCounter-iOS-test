//
//  BaseRepositoryProtocol.swift
//  PillCounter
//
//  Created by HC on 05/11/25.
//

import Foundation

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
    static var shouldBypassSSL: Bool { return false }

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
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
                    throw APIError.invalidResponse
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    do {
                        return try JSONDecoder().decode(T.self, from: data)
                    } catch {
                        Log("⚠️ Parsing error for \(T.self): \(error)")
                        throw APIError.parsingError
                    }
                case 401:
                    NotificationCenter.default.post(name: .unauthorizedResponseReceived, object: nil)
                    throw APIError.unauthorized
                case 403:
                    throw APIError.forbidden
                case 404:
                    throw APIError.notFound
                case 500 where attempt < maxRetries:
                    attempt += 1
                    continue
                case 500...599:
                    throw APIError.serverError(statusCode: httpResponse.statusCode)
                default:
                    throw APIError.serverError(statusCode: httpResponse.statusCode)
                }

            } catch {
                if attempt < maxRetries {
                    attempt += 1
                    continue
                } else {
                    throw APIError.unknown(error)
                }
            }
        }

        throw APIError.serverError(statusCode: 500)
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
class UnsafeSSLManager: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
#endif
