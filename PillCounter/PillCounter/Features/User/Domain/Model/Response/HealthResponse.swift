//
//  HealthResponse.swift
//  PillCounter
//

import Foundation

struct HealthResponse: Codable {
    let status: Int?
    let isSuccess: Bool?
    let message: String?
    let token: String?
    let data: HealthData?

    enum CodingKeys: String, CodingKey {
        case status
        case isSuccess = "is_success"
        case message
        case token
        case data
    }
}

struct HealthData: Codable {
    let isHealthy: Bool?
    let checks: [String: HealthCheckDetail]?
    let checkedAt: String?

    enum CodingKeys: String, CodingKey {
        case isHealthy = "is_healthy"
        case checks
        case checkedAt = "checked_at"
    }
}

struct HealthCheckDetail: Codable {
    let isHealthy: Bool?
    let latencyMs: Double?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case isHealthy = "is_healthy"
        case latencyMs = "latency_ms"
        case detail
    }
}
