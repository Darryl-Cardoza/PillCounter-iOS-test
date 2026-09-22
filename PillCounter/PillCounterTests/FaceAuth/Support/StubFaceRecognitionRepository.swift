//
//  StubFaceRecognitionRepository.swift
//  PillCounterTests
//
//  Scriptable FaceRecognitionRepositoryProtocol for the enrollment view model,
//  injected through its existing `init(repository:)` seam. Only the duplicate
//  path is scriptable — everything else returns a harmless default, since the
//  tests that use this can't drive a real capture anyway (that needs a camera).
//

import Foundation
import CoreData
import CoreVideo
import UIKit
@testable import PillCounter

final class StubFaceRecognitionRepository: FaceRecognitionRepositoryProtocol {

    /// What `checkDuplicateFace` returns. nil = no duplicate.
    var duplicateMatchResult: DuplicateFaceMatch?

    private(set) var checkDuplicateFaceCallCount = 0
    /// How many candidate embeddings the last check was handed — the centre-pose
    /// call should pass exactly one.
    private(set) var lastCandidateCount: Int?

    func checkDuplicateFace(
        against embeddings: [FaceEmbedding], excludingUserId: String?
    ) -> DuplicateFaceMatch? {
        checkDuplicateFaceCallCount += 1
        lastCandidateCount = embeddings.count
        return duplicateMatchResult
    }

    // MARK: - Unused by these tests

    func isNameTaken(_ name: String) -> Bool { false }

    func registerUser(firstName: String, lastName: String) -> FaceUserEntity {
        // Built in the tests' own in-memory stack, never the app's on-disk one.
        let entity = FaceUserEntity(context: MockCoreData.context)
        entity.id = UUID().uuidString
        entity.name = "\(firstName) \(lastName)"
        entity.is_active = true
        return entity
    }

    func generateEnrollmentEmbedding(
        pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult, qualityScore: Float
    ) -> FaceEmbedding? { nil }

    func saveEnrollmentEmbeddings(userId: String, embeddings: [FaceEmbedding]) -> Bool { true }

    func deleteUser(id: String) {}

    func saveAvatar(userId: String, image: UIImage) {}

    func loadAvatar(userId: String) -> UIImage? { nil }

    func loadActiveEnrollments() -> [RegisteredUserEmbeddings] { [] }

    func generateAuthenticationEmbedding(
        pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult
    ) -> FaceEmbedding? { nil }

    func identify(
        embedding: [Float], among registeredUsers: [RegisteredUserEmbeddings]
    ) -> FrameIdentification {
        FrameIdentification(userId: nil, score: 0)
    }
}
