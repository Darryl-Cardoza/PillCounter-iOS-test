//
//  LoginRepository.swift
//  PillCounter
//
//  Created by HC on 11/11/25.
//

import Foundation

protocol LoginRepositoryProtocol {
    
    func sendOTP(email: String) async throws -> SendOTPResponse
    
    func resendOTP(email: String) async throws -> SendOTPResponse
    
    func verifyOTP(email: String, otp: String, fcmToken:String) async throws -> VerifyOTPResponse
    
    func logout(refreshToken: String) async throws -> LogoutResponse
    
}

final class LoginRepository: LoginRepositoryProtocol, BaseRepositoryProtocol {
    
    static let shared = LoginRepository()
    
    private init() {}
    
    func sendOTP(email: String) async throws -> SendOTPResponse {
        // make the body for sending the email in the body. no need to create a request model for this.
        return try await Self.performRequest(
            url: APIConstants.sendOTP,
            method: .post,
            body: [
                "email": email
            ],
            responseType: SendOTPResponse.self
        )
    }
    
    func resendOTP(email: String) async throws -> SendOTPResponse {
        return try await Self.performRequest(
            url: APIConstants.resendOTP,
            method: .post,
            body: [
                "email": email
            ],
            responseType: SendOTPResponse.self
        )
    }
    
    func verifyOTP(email: String, otp: String, fcmToken: String) async throws -> VerifyOTPResponse {
        print("FcmToken is: \(fcmToken)")
        let body: [String: Any] = [
            "email": email,
            "otp": otp,
            "fcm_token": fcmToken
        ]
        return try await Self.performRequest(
            url: APIConstants.verifyOTP,
            method: .post,
            body: body,
            responseType: VerifyOTPResponse.self
        )
    }
    
    func logout(refreshToken: String) async throws -> LogoutResponse {
        // code
        return try await Self.performRequest(
            url: APIConstants.logout,
            method: .post,
            body: [
                "refresh_token": refreshToken
            ],
            responseType: LogoutResponse.self
        )
    }
}
