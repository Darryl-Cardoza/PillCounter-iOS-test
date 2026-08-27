//
//  HealthRepository.swift
//  PillCounter
//

import Foundation

protocol HealthRepositoryProtocol {
    func checkHealth() async throws -> HealthResponse
}

final class HealthRepository: HealthRepositoryProtocol, BaseRepositoryProtocol {

    static let shared = HealthRepository()

    private init() {}

    func checkHealth() async throws -> HealthResponse {
        try await Self.performRequest(
            url: APIConstants.health,
            method: .get,
            responseType: HealthResponse.self
        )
    }
}
