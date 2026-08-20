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
    /// embeddings. Not used by either reference implementation — left here
    /// as the documented extension point the spec asks for, not the default.
    case averageSimilarity
}

final class FaceRecognitionConfig {

    static let shared = FaceRecognitionConfig()
    private init() {}

    /// Minimum cosine similarity a user's candidate score must reach to be
    /// considered a match. Below this, "no match" — never the closest user
    /// anyway (spec section 7/10).
    ///
    /// 0.38 — same value this app's Android FaceMatcher.MATCH_THRESHOLD and
    /// the Python reference use (OpenCV's own FaceRecognizerSF default is
    /// 0.363). Do not raise this back toward 0.6+ without on-device
    /// evidence — SFace's genuine same-identity cosine similarity runs much
    /// lower than that.
    var acceptanceThreshold: Float = 0.38

    /// Minimum lead the best-matching user's score must hold over the best
    /// score from any OTHER user to be accepted, even when the best score
    /// alone clears `acceptanceThreshold`. Without this gate, once two
    /// users' scores land close together (e.g. after an alignment fix
    /// tightens the whole score distribution), whichever is closest by
    /// per-frame noise wins and identity flips between runs. Not from
    /// either reference implementation (they only threshold) — added
    /// because a single global threshold can't distinguish "clearly A"
    /// from "barely A over B."
    var minMarginOverRunnerUp: Float = 0.03

    /// How a user's per-frame candidate score is computed from their stored
    /// embedding set.
    var scoringStrategy: CandidateScoringStrategy = .bestSimilarity

    // MARK: - Performance (spec section 13)

    /// Minimum spacing between recognition attempts, regardless of camera
    /// FPS — matches the Android reference's AUTO_VERIFY_FRAME_INTERVAL_MS
    /// (150ms) exactly.
    var minInferenceIntervalSeconds: TimeInterval = 0.15
}
