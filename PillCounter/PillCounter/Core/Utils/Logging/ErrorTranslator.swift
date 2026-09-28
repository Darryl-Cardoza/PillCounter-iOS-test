import Foundation

public enum ErrorTranslator {
    public static func translate(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        if let urlError = error as? URLError {
            return translate(urlError)
        }
        if error is DecodingError {
            return "The server response could not be understood."
        }
        if let cocoaError = error as? CocoaError {
            return translate(cocoaError)
        }
        if error is CancellationError {
            return "The operation was cancelled."
        }
        return "An unexpected error occurred."
    }

    private static func translate(_ urlError: URLError) -> String {
        switch urlError.code {
        case .timedOut:
            return "The request timed out while communicating with the server."
        case .notConnectedToInternet, .networkConnectionLost:
            return "The device is not connected to the network."
        case .cannotFindHost, .dnsLookupFailed:
            return "Unable to reach the server. Check the network connection."
        case .cannotConnectToHost:
            return "Unable to establish a connection with the server."
        case .cancelled:
            return "The operation was cancelled."
        default:
            return "A network error occurred."
        }
    }

    private static func translate(_ cocoaError: CocoaError) -> String {
        switch cocoaError.code {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return "The requested file could not be found."
        case .fileReadNoPermission, .fileWriteNoPermission:
            return "The application does not have permission to perform this operation."
        default:
            return "A file operation failed."
        }
    }
}
