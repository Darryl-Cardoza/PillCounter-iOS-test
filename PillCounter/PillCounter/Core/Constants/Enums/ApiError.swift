//
//  ApiError.swift
//  PillCounter
//
//  Created by HC on 05/11/25.
//

import SwiftUI

public enum APIError: Error {
    case invalidURL
    case invalidResponse
    case unauthorized       // 401
    case forbidden          // 403
    case notFound           // 404
    case conflict           // 409
    case tooManyRequests    // 429
    case serverError(statusCode: Int)
    case parsingError
    case unknown(Error)
    /// Non-2xx response whose body decoded a server-provided `message` —
    /// carries that text verbatim so callers can show it as-is instead of
    /// a generic status-code message.
    case server(message: String)

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return NSLocalizedString("INVALID_URL", comment: "API error")
        case .invalidResponse:
            return NSLocalizedString("INVALID_RESPONSE", comment: "API error")
        case .unauthorized:
            return NSLocalizedString("UNAUTHORIZED", comment: "API error")
        case .forbidden:
            return NSLocalizedString("FORBIDDEN", comment: "API error")
        case .notFound:
            return NSLocalizedString("NOT_FOUND", comment: "API error")
        case .conflict:
            return NSLocalizedString("TERMINAL_ALREADY_CLAIMED", comment: "API error")
        case .tooManyRequests:
            return NSLocalizedString("TOO_MANY_REQUESTS", comment: "API error")
        case .serverError(let statusCode):
            let format = NSLocalizedString("SERVER_ERROR", comment: "API error")
            return String(format: format, statusCode)
        case .parsingError:
            return NSLocalizedString("PARSING_ERROR", comment: "API error")
        case .unknown(let error):
            let format = NSLocalizedString("UNKNOWN_ERROR", comment: "API error")
            return String(format: format, error.localizedDescription)
        case .server(let message):
            return message
        }
    }
}

