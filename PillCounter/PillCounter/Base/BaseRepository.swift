//
//  BaseRepositoryProtocol.swift
//  PillCounter
//
//  Created by HC on 05/11/25.
//

import Foundation

/// A reusable base repository protocol that provides a default implementation for network requests.
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
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Headers
        var allHeaders = headers(accessToken)
        if let extra = extraHeaders {
            allHeaders.merge(extra) { (_, new) in new }  // override duplicates
        }
        request.allHTTPHeaderFields = allHeaders

        // Body
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        logRequest(request, body: body)

        // ------------------------------------------------------------------
        // SESSION SELECTION (SSL BYPASS LOGIC)
        // ------------------------------------------------------------------
        let session: URLSession
        if shouldBypassSSL {
            // Create a custom session with the Unsafe Delegate
            session = URLSession(
                configuration: .default,
                delegate: UnsafeSSLManager(),
                delegateQueue: nil
            )
        } else {
            // Use the standard secure shared session
            session = URLSession.shared
        }
        // ------------------------------------------------------------------

        var attempt = 0
        let maxRetries = 2

        while attempt <= maxRetries {
            do {
                // NOTE: We use 'session' here, not 'URLSession.shared'
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
                        throw APIError.parsingError
                    }
                case 401:
                    throw APIError.unauthorized
                case 403:
                    throw APIError.forbidden
                case 404:
                    throw APIError.notFound
                case 500 where attempt < maxRetries:
                    attempt += 1
                    continue
                case 500...599:
                    throw APIError.serverError(
                        statusCode: httpResponse.statusCode)
                default:
                    throw APIError.serverError(
                        statusCode: httpResponse.statusCode)
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

        throw APIError.serverError(statusCode: 500)  // failsafe
    }

    // MARK: - Headers
    static func headers(_ accessToken: String?) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
//            "X-Server-Key": ConfigurationManager.shared.xServerKey,
            "X-Server-Key": "d1ff4797acb7147205bb249cce918f23a4f8e54a8d56488d79e83abcdf1b24f6f1ccc9af5dea3c1a1b5e2b6aa247ff55ac8e12f165974f8cfce41328f7ea447e",
        ]

        if let token = accessToken, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }

        return headers
    }
    
    private static func logRequest(_ request: URLRequest, body: [String: Any]?) {
        #if DEBUG
        print("\n========================= 🌐 API REQUEST =========================")
        print("➡️ URL: \(request.url?.absoluteString ?? "nil")")
        print("➡️ Method: \(request.httpMethod ?? "nil")")

        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            print("➡️ Headers:")
            headers.forEach { key, value in
                print("   \(key): \(value)")
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
// This class intercepts the SSL Handshake and blindly trusts the server.
// Equivalent to Flutter's: ..badCertificateCallback = (cert, host, port) => true
class UnsafeSSLManager: NSObject, URLSessionDelegate {
    
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        // 1. Check if the challenge is for Server Trust (SSL Certificate)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            
            // 2. Create a credential from the trust object
            let credential = URLCredential(trust: serverTrust)
            
            // 3. Tell URLSession to USE this credential (trusting it), regardless of validity
            completionHandler(.useCredential, credential)
        } else {
            // 4. For all other auth types (like Basic Auth), perform default handling
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
