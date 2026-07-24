//
//  UserRepository.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

protocol UserRepositoryProtocol {

    func getUser(accessToken: String, currentAppVersion: String, fcmToken: String) async throws -> UserResponse

    func updateUserProfile(
        request: UpdateUserProfileRequest, accessToken: String
    ) async throws -> UserResponse

    func deleteUserProfile(accessToken: String) async throws
        -> DeleteUserResponse

    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse

    func updateTerminal(terminalId: String, terminalName: String, isActive: Bool, accessToken: String) async throws -> UpdateTerminalResponse

    func getPharmacyTypes(accessToken: String) async throws -> PharmacyTypeResponse

    func getCountries(accessToken: String) async throws -> CountryResponse
}


final class UserRepository: UserRepositoryProtocol, BaseRepositoryProtocol {
    
    static let shared = UserRepository()
    
    private init() {}

    func getUser(accessToken: String, currentAppVersion: String, fcmToken: String) async throws -> UserResponse {
        
        let body: [String: Any] = [:]

        return try await Self.performRequest(
            url: APIConstants.getMe,
            method: .post,
            accessToken: accessToken,
            body: body,
            responseType: UserResponse.self
        )
    }

    func updateUserProfile(
        request: UpdateUserProfileRequest,
        accessToken: String
    ) async throws -> UserResponse {
        // convert the request model to [String: Any] model
        let body =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(request)
            ) as? [String: Any]

        return try await Self.performRequest(
            url: APIConstants.updateProfile,
            method: .post,
            accessToken: accessToken,
            body: body,
            responseType: UserResponse.self
        )
    }

    func deleteUserProfile(accessToken: String) async throws
        -> DeleteUserResponse
    {
        return try await Self.performRequest(
            url: APIConstants.deleteProfile,
            method: .delete,
            accessToken: accessToken,
            responseType: DeleteUserResponse.self
        )
    }

    // Adding the drug service over here only, if the drug module increases separately make the repo for drugs.
//    func getDrug(ndc: String) async throws -> GetDrugResponse {
//
//        return try await Self.performRequest(
//            url: "\(APIConstants.getDrugInfo)/\(ndc)",
//            method: .get,
//            responseType: GetDrugResponse.self
//        )
//    }
//    
    func updateTerminal(terminalId: String, terminalName: String, isActive: Bool, accessToken: String) async throws -> UpdateTerminalResponse {
        let body: [String: Any] = [
            "terminal_name": terminalName,
            "is_active": isActive
        ]
        return try await Self.performRequest(
            url: APIConstants.updateTerminal(terminalId: terminalId),
            method: .put,
            accessToken: accessToken,
            body: body,
            responseType: UpdateTerminalResponse.self
        )
    }

    func getPharmacyTypes(accessToken: String) async throws -> PharmacyTypeResponse {
        return try await Self.performRequest(
            url: APIConstants.pharmacyTypes,
            method: .get,
            accessToken: accessToken,
            responseType: PharmacyTypeResponse.self
        )
    }

    func getCountries(accessToken: String) async throws -> CountryResponse {
        return try await Self.performRequest(
            url: APIConstants.countries,
            method: .get,
            accessToken: accessToken,
            responseType: CountryResponse.self
        )
    }

    // refresh token to refresh the access token.
    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse {
        
        return try await Self.performRequest(
            url: APIConstants.refreshToken,
            method: .post,
            body: [
                "refresh_token": refreshToken
            ],
            responseType: RefreshTokenResponse.self
        )
    }
}
