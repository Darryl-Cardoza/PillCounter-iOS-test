import Foundation

/// Matches the ingest endpoint's documented schema. `context` values are
/// stringified (`[String: Any]` isn't `Encodable`) — acceptable since context is
/// opportunistic debug metadata, not a typed contract.
struct RemoteLogPayload: Encodable {
    struct ErrorInfo: Encodable {
        let type: String?
        let message: String?
        let stackTrace: String?
        let isFatal: Bool

        enum CodingKeys: String, CodingKey {
            case type, message
            case stackTrace = "stack_trace"
            case isFatal = "is_fatal"
        }
    }

    struct NetworkInfo: Encodable {
        let type: String
        let isOnline: Bool

        enum CodingKeys: String, CodingKey {
            case type
            case isOnline = "is_online"
        }
    }

    let deviceKey: String
    let appName: String
    let appVersion: String
    var buildNumber: String?
    let platform: String
    let osVersion: String
    let deviceModel: String
    let sessionId: String
    let logId: String
    let severity: Int
    let timestamp: String
    let message: String
    let tag: String
    let event: String
    let context: [String: String]?
    let error: ErrorInfo?
    let network: NetworkInfo

    enum CodingKeys: String, CodingKey {
        case deviceKey = "device_key"
        case appName = "app_name"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case sessionId = "session_id"
        case logId = "log_id"
        case severity, timestamp, message, tag, event, context, error, network
    }
}
