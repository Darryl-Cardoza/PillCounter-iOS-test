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
    /// 0.38 — same value this app's Android FaceMatcher.MATCH_THRESHOLD and
    /// the Python reference use (OpenCV's own FaceRecognizerSF default is
    /// 0.363). Do not raise this back toward 0.6+ without on-device
    /// evidence — SFace's genuine same-identity cosine similarity runs much
    /// lower than that.
    var acceptanceThreshold: Float = 0.38

    /// Absolute floor the best score must clear on top of
    /// `acceptanceThreshold`, applied regardless of how many users are
    /// enrolled. This is the gate that actually protects the single-enrolled-
    /// user case, where `minMarginOverRunnerUp` below is structurally unable
    /// to reject anything (there is no runner-up to lead).
    ///
    /// 0.55 — midpoint of scores measured on-device with one enrolled user:
    /// an UNENROLLED person scored 0.391 (a false accept under the bare 0.38
    /// threshold), the genuine enrolled user scored 0.715. 0.55 sits 0.16
    /// above the false accept and 0.165 below the genuine match. If a genuine
    /// user is ever rejected, re-read the identify() debug scores before
    /// moving this — overlapping ranges would mean no threshold can separate
    /// them and the problem is upstream in capture quality.
    var minAbsoluteAcceptScore: Float = 0.55

    /// Minimum lead the best-matching user's score must hold over the best
    /// score from any OTHER user to be accepted, even when the best score
    /// alone clears `acceptanceThreshold`. Without this gate, once two
    /// users' scores land close together (e.g. after an alignment fix
    /// tightens the whole score distribution), whichever is closest by
    /// per-frame noise wins and identity flips between runs. Not from
    /// either reference implementation (they only threshold) — added
    /// because a single global threshold can't distinguish "clearly A"
    /// from "barely A over B."
    ///
    /// 0.10 (raised from 0.03) — 0.03 was too thin to reject real near-ties
    /// between different people's embeddings, causing false accepts. Needs
    /// on-device tuning against real enrolled users.
    var minMarginOverRunnerUp: Float = 0.10

    /// How a user's per-frame candidate score is computed from their stored
    /// embedding set.
    var scoringStrategy: CandidateScoringStrategy = .averageSimilarity

    // MARK: - Performance (spec section 13)

    /// Minimum spacing between recognition attempts, regardless of camera
    /// FPS — matches the Android reference's AUTO_VERIFY_FRAME_INTERVAL_MS
    /// (150ms) exactly.
    var minInferenceIntervalSeconds: TimeInterval = 0.15
}
