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
    case serverError(statusCode: Int)
    case parsingError
    case unknown(Error)
    
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
        case .serverError(let statusCode):
            let format = NSLocalizedString("SERVER_ERROR", comment: "API error")
            return String(format: format, statusCode)
        case .parsingError:
            return NSLocalizedString("PARSING_ERROR", comment: "API error")
        case .unknown(let error):
            let format = NSLocalizedString("UNKNOWN_ERROR", comment: "API error")
            return String(format: format, error.localizedDescription)
        }
    }
}

