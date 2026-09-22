//
//  FaceRecognitionConfig.swift
//  PillCounter
//
//  Single configuration surface for authentication-time tuning knobs, kept
//  separate from FaceQualityChecker's enrollment/capture thresholds so the
//  acceptance threshold can be calibrated against real test data without
//  touching detection code (spec section 7).
//
//  SIMILARITY METRIC: cosine similarity, consistently, everywhere in the
//  app (FaceEmbedding.cosineSimilarity — enrollment's duplicate-check and
//  authentication's identification both use it).
//
//  Values below are copied verbatim from this app's own proven-working
//  Android implementation (FaceMatcher.MATCH_THRESHOLD, FaceAuthViewModel's
//  AUTO_VERIFY_FRAME_INTERVAL_MS) and the standalone Python reference
//  (MATCH_THRESHOLD, matching OpenCV's FaceRecognizerSF default of 0.363) —
//  not independently guessed.
//

import Foundation

/// How a user's candidate score is derived from their set of stored
/// embeddings vs. the current live embedding. Isolated behind this enum
/// (spec section 6: "keep this logic isolated so it can later be changed to
/// an aggregate score") — `identify(...)` in FaceRecognitionRepository
/// switches on it, callers never inline the math themselves.
enum CandidateScoringStrategy {
    /// The user's score is their single best-matching stored embedding.
    /// Matches both the Android (`FaceMatcher.identify`) and Python
    /// (`identify()`) reference implementations exactly.
    case bestSimilarity
    /// The user's score is the mean similarity across all their stored
    /// embeddings. Not used by either reference implementation, but is the
    /// default here — bestSimilarity let one noisy oblique-angle embedding
    /// spike a non-matching user's score past threshold (false accepts).
    case averageSimilarity
}

final class FaceRecognitionConfig {

    static let shared = FaceRecognitionConfig()
    private init() {}

    /// Minimum cosine similarity a user's candidate score must reach to be
    /// considered a match. Below this, "no match" — never the closest user
    /// anyway (spec section 7/10).
    ///
    /// 0.60 — this app's current Android FaceMatcher.MATCH_THRESHOLD. It was
    /// 0.38 here (Android's old value, and OpenCV's FaceRecognizerSF default
    /// of 0.363), which was low enough to need an absolute floor and a
    /// runner-up margin bolted on top to stop false accepts. Android raised
    /// the threshold instead and dropped both extra gates; this now matches.
    ///
    /// Deliberately a single gate: two people who share a face must BOTH be
    /// able to unlock (enrollment allows a duplicate through an explicit
    /// warning), and a runner-up margin structurally cannot allow that.
    var acceptanceThreshold: Float = 0.60

    /// How a user's per-frame candidate score is computed from their stored
    /// embedding set.
    ///
    /// `.bestSimilarity` matches Android's FaceMatcher.identify and the Python
    /// reference: the gallery is flat and the single best-scoring embedding
    /// wins. Was `.averageSimilarity` here, which only existed to stop one
    /// noisy oblique embedding spiking a non-matching user past the old 0.38
    /// threshold — at 0.60 that is no longer the cheapest fix, and averaging
    /// penalises a genuine user whose turned-head embeddings score lower.
    var scoringStrategy: CandidateScoringStrategy = .bestSimilarity

    // MARK: - Performance (spec section 13)

    /// Minimum spacing between recognition attempts, regardless of camera
    /// FPS — matches the Android reference's AUTO_VERIFY_FRAME_INTERVAL_MS
    /// (150ms) exactly.
    var minInferenceIntervalSeconds: TimeInterval = 0.15
}
