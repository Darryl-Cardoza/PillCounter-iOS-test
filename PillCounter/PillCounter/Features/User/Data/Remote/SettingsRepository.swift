//
//  SettingsRepository.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

protocol SettingsRepositoryProtocol {
    func getMobileSettings(currentVersion: String) async throws -> MobileSettingsResponse
}

final class SettingsRepository: SettingsRepositoryProtocol, BaseRepositoryProtocol {
    
    static let shared = SettingsRepository()
    
    private init () {}
    
    func getMobileSettings(currentVersion: String) async throws -> MobileSettingsResponse {
        return try await Self.performRequest(
            url: "\(APIConstants.getMobileSettings)=ios",
            method: .get,
            responseType: MobileSettingsResponse.self
        )
    }
}
