//
//  ControlledRepository.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/03/26.
//
import Foundation


protocol ControlledRepositoryProtocol {
    func getControlledDrugInfo(ndcValidationRequest: NdcValidationRequest) async throws -> NdcComparisonResponse
}


final class ControlledRepository: ControlledRepositoryProtocol, BaseRepositoryProtocol {
    
    static let shared = ControlledRepository() // singleton instance.

    func getControlledDrugInfo(ndcValidationRequest: NdcValidationRequest) async throws -> NdcComparisonResponse {
        
        let body =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(ndcValidationRequest)
            ) as? [String: Any]
        
        return try await Self.performRequest(
            url: "\(APIConstants.getControlledDrugInfo)",
            method: .post,
            body: body,
            responseType: NdcComparisonResponse.self
        )
    }
}
    
