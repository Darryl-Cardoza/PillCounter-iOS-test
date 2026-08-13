//
//  FaceMatchCalibrationTests.swift
//  PillCounterTests
//
//  MEASUREMENT HARNESS, not a pass/fail unit test.
//
//  Purpose: derive FaceRecognitionConfig.acceptanceThreshold and
//  minMarginOverRunnerUp from measured data instead of picking a number.
//
//  Why this exists: the shipped threshold (0.38) was taken from OpenCV's
//  FaceRecognizerSF default (0.363), which is a 1:1 VERIFICATION operating
//  point — "are these two faces the same person?". This app performs 1:N
//  OPEN-SET IDENTIFICATION — "which, if any, of N enrolled users is this?".
//  Those need different thresholds. Identification takes a maximum over many
//  impostor comparisons (per user: max over their stored embeddings; then max
//  across users), and the maximum of many impostor draws sits far above any
//  single draw. Reusing a 1:1 threshold for 1:N therefore admits strangers.
//  This harness quantifies by how much, on real data, so the fix is a
//  measured number that iOS and Android can both adopt.
//
//  Run:
//    xcodebuild test -scheme PillCounter \
//      -only-testing:PillCounterTests/FaceMatchCalibrationTests \
//      -parallel-testing-enabled NO
//
//  The report prints unconditionally (see `Report.emit`) so the numbers are
//  readable in console/CI output even when nothing fails.
//
//  IMPORTANT: with no real enrolled data present this harness records a
//  skip — it never silently "passes". Synthetic vectors cannot calibrate a
//  real threshold, because the score distribution is a property of SFace plus
//  this app's alignment pipeline, not of arbitrary numbers.
//

import Foundation
import Testing
@testable import PillCounter

// MARK: - Fixture model

/// One identity's embeddings. `identityId` groups samples of the SAME person;
/// it is NOT necessarily a Core Data user id (an impostor identity is enrolled
/// nowhere).
struct CalibrationIdentity {
    let identityId: String
    let label: String
    /// Each element is one embedding vector for this identity.
    let embeddings: [[Float]]
    /// False for identities that must never match anyone — the strangers whose
    /// scores reveal the real false-accept risk.
    let isEnrolled: Bool
}

// MARK: - Score collection

/// Genuine and impostor cosine-similarity samples, kept separate.
struct ScoreDistributions {
    var genuine: [Float] = []
    var impostor: [Float] = []

    /// Highest impostor score seen, with the pair that produced it. This single
    /// number is the practical floor for any safe threshold: a threshold at or
    /// below it admits that stranger.
    var worstImpostor: (score: Float, detail: String)?
}

enum CalibrationEngine {

    /// Builds both distributions from a fixture set.
    ///
    /// Genuine pairs use leave-one-out WITHIN an identity, so a vector is never
    /// compared against itself (self-similarity is always 1.0 and would inflate
    /// the genuine distribution into meaninglessness). Only enrolled identities
    /// contribute genuine pairs — an impostor has no legitimate match.
    ///
    /// Impostor pairs are every cross-identity comparison, in BOTH directions:
    /// unenrolled-probe-vs-enrolled-template (the reported bug) and
    /// enrolled-vs-different-enrolled (identity confusion between real users).
    static func distributions(from identities: [CalibrationIdentity]) -> ScoreDistributions {
        var result = ScoreDistributions()

        for identity in identities where identity.isEnrolled {
            let vectors = identity.embeddings
            guard vectors.count > 1 else { continue }
            for i in 0..<vectors.count {
                for j in (i + 1)..<vectors.count {
                    result.genuine.append(
                        FaceEmbedding.cosineSimilarity(vectors[i], vectors[j])
                    )
                }
            }
        }

        for probe in identities {
            for template in identities where template.identityId != probe.identityId {
                // Only enrolled identities have templates to match against.
                guard template.isEnrolled else { continue }
                for probeVector in probe.embeddings {
                    for templateVector in template.embeddings {
                        let score = FaceEmbedding.cosineSimilarity(probeVector, templateVector)
                        result.impostor.append(score)
                        if score > (result.worstImpostor?.score ?? -.infinity) {
                            result.worstImpostor = (
                                score, "\(probe.label) vs \(template.label)"
                            )
                        }
                    }
                }
            }
        }

        return result
    }

    /// Reproduces production per-user scoring so the sweep measures what the
    /// app actually does. Delegates the metric to `FaceEmbedding` and mirrors
    /// `FaceRecognitionRepository.candidateScore`'s two strategies — if that
    /// logic changes, this must change with it or the calibration stops
    /// describing production.
    static func candidateScore(
        probe: [Float], template: [[Float]], strategy: CandidateScoringStrategy
    ) -> Float {
        guard !template.isEmpty else { return -1 }
        let similarities = template.map { FaceEmbedding.cosineSimilarity(probe, $0) }
        switch strategy {
        case .bestSimilarity:
            return similarities.max() ?? -1
        case .averageSimilarity:
            return similarities.reduce(0, +) / Float(similarities.count)
        }
    }
}

// MARK: - Full-pipeline sweep

/// Outcome of running one probe embedding through the real 1:N gate.
struct GateOutcome {
    let matchedUserId: String?
    let bestScore: Float
    let runnerUpScore: Float
}

enum GateSimulator {

    /// Mirrors `FaceRecognitionRepository.identify` INCLUDING the margin gate,
    /// so the sweep reflects the combined threshold+margin decision rather than
    /// the threshold alone.
    ///
    /// NOTE the `max(runnerUpScore, 0)` clamp is reproduced deliberately: it is
    /// current production behavior, and with a single enrolled identity it makes
    /// margin == bestScore, which means the margin gate always passes. The sweep
    /// must show that defect, not hide it.
    static func identify(
        probe: [Float],
        templates: [(userId: String, vectors: [[Float]])],
        threshold: Float,
        minMargin: Float,
        strategy: CandidateScoringStrategy
    ) -> GateOutcome {
        var bestUserId: String?
        var bestScore: Float = -1
        var runnerUpScore: Float = -1

        for template in templates {
            let score = CalibrationEngine.candidateScore(
                probe: probe, template: template.vectors, strategy: strategy
            )
            if score > bestScore {
                runnerUpScore = bestScore
                bestScore = score
                bestUserId = template.userId
            } else if score > runnerUpScore {
                runnerUpScore = score
            }
        }

        let margin = bestScore - max(runnerUpScore, 0)
        guard let bestUserId, bestScore >= threshold, margin >= minMargin else {
            return GateOutcome(matchedUserId: nil, bestScore: bestScore, runnerUpScore: runnerUpScore)
        }
        return GateOutcome(matchedUserId: bestUserId, bestScore: bestScore, runnerUpScore: runnerUpScore)
    }
}

/// One row of the sweep: how a given threshold behaves on the fixture set.
struct SweepRow {
    let threshold: Float
    /// Fraction of unenrolled probes wrongly matched to some user (per frame).
    let falseAcceptRate: Double
    /// Fraction of enrolled probes not matched to their own identity (per frame).
    let falseRejectRate: Double
    /// Fraction of enrolled probes matched to the WRONG user — a distinct and
    /// more serious failure than a plain reject.
    let misidentifyRate: Double

    /// Probability that a stranger gets in at least once across a scanning
    /// session, given K consecutive same-user frames are required.
    ///
    /// Models frames as independent, which they are NOT — consecutive camera
    /// frames of a held-still face are highly correlated, so real session FAR
    /// is HIGHER than this. Treat this column as a lower bound / best case, and
    /// rely on the on-device impostor test for the true figure.
    func sessionFalseAcceptRate(framesPerSession: Int, requiredConsecutive K: Int) -> Double {
        guard falseAcceptRate > 0 else { return 0 }
        guard K > 1 else {
            return 1 - pow(1 - falseAcceptRate, Double(framesPerSession))
        }
        let runProbability = pow(falseAcceptRate, Double(K))
        let opportunities = max(0, framesPerSession - K + 1)
        return 1 - pow(1 - runProbability, Double(opportunities))
    }
}

enum ThresholdSweep {

    /// Sweeps `range` and reports per-frame FAR/FRR/misidentification using the
    /// full production gate. Each probe is scored leave-one-out: the probe
    /// vector is removed from its own template, otherwise a genuine probe
    /// trivially matches itself at 1.0 and FRR reads as artificially perfect.
    static func run(
        identities: [CalibrationIdentity],
        from lower: Float = 0.30,
        to upper: Float = 0.75,
        step: Float = 0.01,
        minMargin: Float,
        strategy: CandidateScoringStrategy
    ) -> [SweepRow] {
        let enrolled = identities.filter(\.isEnrolled)
        let strangers = identities.filter { !$0.isEnrolled }

        var rows: [SweepRow] = []
        var threshold = lower
        while threshold <= upper + 1e-6 {
            var falseAccepts = 0, strangerProbes = 0
            var correct = 0, misidentified = 0, rejected = 0, genuineProbes = 0

            for stranger in strangers {
                for probe in stranger.embeddings {
                    strangerProbes += 1
                    let templates = enrolled.map { ($0.identityId, $0.embeddings) }
                    let outcome = GateSimulator.identify(
                        probe: probe, templates: templates,
                        threshold: threshold, minMargin: minMargin, strategy: strategy
                    )
                    if outcome.matchedUserId != nil { falseAccepts += 1 }
                }
            }

            for identity in enrolled {
                for (index, probe) in identity.embeddings.enumerated() {
                    genuineProbes += 1
                    // Leave-one-out: drop this probe from its own template.
                    let templates = enrolled.map { candidate -> (String, [[Float]]) in
                        guard candidate.identityId == identity.identityId else {
                            return (candidate.identityId, candidate.embeddings)
                        }
                        var reduced = candidate.embeddings
                        reduced.remove(at: index)
                        return (candidate.identityId, reduced)
                    }.filter { !$0.1.isEmpty }

                    let outcome = GateSimulator.identify(
                        probe: probe, templates: templates,
                        threshold: threshold, minMargin: minMargin, strategy: strategy
                    )
                    switch outcome.matchedUserId {
                    case .some(identity.identityId): correct += 1
                    case .some: misidentified += 1
                    case .none: rejected += 1
                    }
                }
            }

            rows.append(
                SweepRow(
                    threshold: threshold,
                    falseAcceptRate: strangerProbes > 0
                        ? Double(falseAccepts) / Double(strangerProbes) : 0,
                    falseRejectRate: genuineProbes > 0
                        ? Double(rejected) / Double(genuineProbes) : 0,
                    misidentifyRate: genuineProbes > 0
                        ? Double(misidentified) / Double(genuineProbes) : 0
                )
            )
            threshold += step
        }
        return rows
    }
}

// MARK: - Reporting

enum Report {

    static func emit(_ text: String) {
        // print, not Log — this must reach console/CI output verbatim and is
        // not app telemetry. Never print raw embedding vectors here: they are
        // biometric PII (see FaceEmbedding.vector). Aggregate scores only.
        print(text)
    }

    static func percentiles(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "n=0" }
        let sorted = values.sorted()
        func at(_ p: Double) -> Float {
            let index = min(sorted.count - 1, max(0, Int((p * Double(sorted.count - 1)).rounded())))
            return sorted[index]
        }
        let mean = sorted.reduce(0, +) / Float(sorted.count)
        return String(
            format: "n=%d min=%.3f p05=%.3f p50=%.3f mean=%.3f p95=%.3f max=%.3f",
            sorted.count, sorted[0], at(0.05), at(0.50), mean, at(0.95), sorted[sorted.count - 1]
        )
    }

    static func distributionSummary(_ distributions: ScoreDistributions) -> String {
        var lines = [
            "",
            "=== FACE MATCH CALIBRATION ===",
            "genuine  : \(percentiles(distributions.genuine))",
            "impostor : \(percentiles(distributions.impostor))",
        ]
        if let worst = distributions.worstImpostor {
            lines.append(
                String(format: "worst impostor pair: %.3f  (%@)", worst.score, worst.detail)
            )
        }
        // Separation is the decision-relevant number: the gap between the
        // weakest genuine pair and the strongest impostor pair. If it is
        // negative the distributions OVERLAP and no single global threshold can
        // separate them — that is a signal to fix alignment/enrollment quality
        // or add score normalization, not to keep tuning the threshold.
        if let minGenuine = distributions.genuine.min(),
           let maxImpostor = distributions.impostor.max() {
            let gap = minGenuine - maxImpostor
            lines.append(String(format: "separation (min genuine - max impostor): %+.3f", gap))
            lines.append(
                gap > 0
                    ? "  distributions are SEPARABLE — pick a threshold inside the gap"
                    : "  distributions OVERLAP — no global threshold separates all cases; "
                      + "prefer the lowest-FAR row below and add multi-frame confirmation"
            )
        }
        return lines.joined(separator: "\n")
    }

    static func sweepTable(_ rows: [SweepRow], framesPerSession: Int, K: Int) -> String {
        var lines = [
            "",
            "--- threshold sweep (per-frame rates; session FAR assumes K=\(K) of "
                + "\(framesPerSession) frames, independence => optimistic) ---",
            "thresh |   FAR  |   FRR  | misID  | sessionFAR(K=1) | sessionFAR(K=\(K))",
        ]
        for row in rows {
            lines.append(
                String(
                    format: "%.2f   | %6.2f%% | %6.2f%% | %6.2f%% | %14.2f%% | %14.4f%%",
                    row.threshold,
                    row.falseAcceptRate * 100,
                    row.falseRejectRate * 100,
                    row.misidentifyRate * 100,
                    row.sessionFalseAcceptRate(framesPerSession: framesPerSession, requiredConsecutive: 1) * 100,
                    row.sessionFalseAcceptRate(framesPerSession: framesPerSession, requiredConsecutive: K) * 100
                )
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Lowest threshold achieving zero per-frame false accepts AND zero
    /// misidentification. Recommends by security first, then reports the
    /// genuine-rejection cost so the tradeoff is explicit rather than implied.
    static func recommendation(_ rows: [SweepRow]) -> String {
        guard let safest = rows.first(where: {
            $0.falseAcceptRate == 0 && $0.misidentifyRate == 0
        }) else {
            return "\nNO threshold in the swept range reaches zero false accepts. "
                + "Do NOT ship a threshold-only fix: multi-frame confirmation is required, "
                + "and enrollment/alignment quality needs investigation."
        }
        return String(
            format: "\nRECOMMENDED acceptanceThreshold = %.2f "
                + "(per-frame FAR 0%%, misID 0%%, FRR %.2f%%)\n"
                + "Apply the SAME value to Android — the defect is shared matching policy.",
            safest.threshold, safest.falseRejectRate * 100
        )
    }
}

// MARK: - Fixtures

enum CalibrationFixtures {

    /// Reads identities from a JSON file whose path comes from the
    /// FACE_CALIBRATION_FIXTURE environment variable.
    ///
    /// Shape: [{"identityId","label","isEnrolled",
    ///          "embeddings":[[Float],...]}]
    ///
    /// Produce it from a device build that has several users enrolled (export
    /// each user's stored embeddings via FaceEmbedding.unpack), and include at
    /// least one identity with "isEnrolled": false — a person enrolled nowhere.
    /// Without a stranger in the set the FAR column is structurally 0 and the
    /// harness cannot measure the reported bug.
    static func loadFromEnvironment() -> [CalibrationIdentity]? {
        guard let path = ProcessInfo.processInfo.environment["FACE_CALIBRATION_FIXTURE"],
              !path.isEmpty else { return nil }
        guard let data = FileManager.default.contents(atPath: path) else {
            Report.emit("FACE_CALIBRATION_FIXTURE set to \(path) but the file is unreadable")
            return nil
        }
        struct RawIdentity: Decodable {
            let identityId: String
            let label: String?
            let isEnrolled: Bool?
            let embeddings: [[Float]]
        }
        do {
            let raw = try JSONDecoder().decode([RawIdentity].self, from: data)
            return raw.map {
                CalibrationIdentity(
                    identityId: $0.identityId,
                    label: $0.label ?? $0.identityId,
                    embeddings: $0.embeddings,
                    isEnrolled: $0.isEnrolled ?? true
                )
            }
        } catch {
            Report.emit("FACE_CALIBRATION_FIXTURE failed to decode: \(error)")
            return nil
        }
    }

    /// Falls back to whatever is already enrolled in the local Core Data store.
    ///
    /// Useful on a device/simulator that has been used for real enrollment. It
    /// yields genuine pairs and enrolled-vs-enrolled impostor pairs, but no
    /// stranger probes — so FAR cannot be measured this way. Reported as such.
    static func loadFromLocalStore() -> [CalibrationIdentity] {
        FaceRecognitionRepository.shared.loadActiveEnrollments().map {
            CalibrationIdentity(
                identityId: $0.userId,
                label: $0.userName,
                embeddings: $0.embeddings,
                isEnrolled: true
            )
        }
    }
}

// MARK: - Tests

@Suite(.serialized)
struct FaceMatchCalibrationTests {

    /// Frames a user typically presents during one scan attempt: roughly 3s at
    /// the production 150ms `minInferenceIntervalSeconds` cadence.
    private static let framesPerSession = 20
    /// Candidate K for multi-frame confirmation, reported alongside K=1 so the
    /// benefit of requiring consecutive agreement is visible in the table.
    private static let candidateK = 3

    @Test func calibrateAcceptanceThreshold() throws {
        let fixtureIdentities = CalibrationFixtures.loadFromEnvironment()
        let identities = fixtureIdentities ?? CalibrationFixtures.loadFromLocalStore()

        guard identities.count >= 2 else {
            withKnownIssue(
                "No calibration data. Set FACE_CALIBRATION_FIXTURE to a JSON export "
                + "with >=2 identities (including >=1 with isEnrolled:false), or run on a "
                + "device with multiple users enrolled. Synthetic vectors cannot calibrate "
                + "a real threshold."
            ) {
                Issue.record("insufficient calibration identities: \(identities.count)")
            }
            return
        }

        let strategy = FaceRecognitionConfig.shared.scoringStrategy
        let minMargin = FaceRecognitionConfig.shared.minMarginOverRunnerUp

        let distributions = CalibrationEngine.distributions(from: identities)
        Report.emit(Report.distributionSummary(distributions))

        let strangerCount = identities.filter { !$0.isEnrolled }.count
        Report.emit(
            "\nidentities=\(identities.count) enrolled=\(identities.count - strangerCount) "
            + "strangers=\(strangerCount)  strategy=\(strategy) minMargin=\(minMargin)"
        )
        if strangerCount == 0 {
            Report.emit(
                "WARNING: no unenrolled identity in the fixture set — the FAR column below "
                + "measures only enrolled-vs-enrolled confusion, NOT the reported "
                + "stranger-accepted bug. Add an isEnrolled:false identity to measure it."
            )
        }

        let rows = ThresholdSweep.run(
            identities: identities, minMargin: minMargin, strategy: strategy
        )
        Report.emit(
            Report.sweepTable(rows, framesPerSession: Self.framesPerSession, K: Self.candidateK)
        )
        Report.emit(Report.recommendation(rows))

        // Report the shipped threshold's measured behavior explicitly — this is
        // the evidence the code comment in FaceRecognitionConfig asked for
        // before changing the value.
        let shipped = FaceRecognitionConfig.shared.acceptanceThreshold
        if let row = rows.min(by: { abs($0.threshold - shipped) < abs($1.threshold - shipped) }) {
            Report.emit(
                String(
                    format: "\nshipped threshold %.2f -> per-frame FAR %.2f%%, "
                        + "session FAR(K=1, %d frames) %.2f%%",
                    shipped, row.falseAcceptRate * 100, Self.framesPerSession,
                    row.sessionFalseAcceptRate(
                        framesPerSession: Self.framesPerSession, requiredConsecutive: 1
                    ) * 100
                )
            )
        }

        #expect(!rows.isEmpty)
    }

    /// Guards the harness's own correctness: a probe must never be compared
    /// against itself when computing genuine pairs, or FRR reads as perfect and
    /// the sweep silently becomes useless. Uses synthetic vectors deliberately —
    /// this asserts harness logic, not a threshold.
    @Test func genuinePairsExcludeSelfComparison() {
        let identity = CalibrationIdentity(
            identityId: "solo", label: "Solo",
            embeddings: [[1, 0, 0, 0], [1, 0, 0, 0]], isEnrolled: true
        )
        let distributions = CalibrationEngine.distributions(from: [identity])
        // 2 vectors => exactly 1 unordered pair, not 4 self-inclusive pairs.
        #expect(distributions.genuine.count == 1)
        #expect(distributions.impostor.isEmpty)
    }

    /// Documents the inert margin gate as an executable fact: with a single
    /// enrolled identity, `max(runnerUpScore, 0)` makes margin == bestScore, so
    /// any score clearing the threshold also clears the margin requirement.
    /// The margin gate therefore provides NO protection in the single-user case,
    /// which is the most common real-world configuration.
    @Test func marginGateIsInertWithSingleEnrolledUser() {
        let template: [[Float]] = [[1, 0, 0, 0]]
        // Deliberately mediocre similarity: clears 0.38, nowhere near a match.
        let probe: [Float] = [0.45, 0.893, 0, 0]

        let outcome = GateSimulator.identify(
            probe: probe, templates: [("only-user", template)],
            threshold: 0.38, minMargin: 0.03, strategy: .bestSimilarity
        )

        #expect(outcome.runnerUpScore == -1)
        #expect(outcome.matchedUserId == "only-user")
    }

    /// Shows why `.bestSimilarity` amplifies false accepts: a stranger who
    /// happens to spike against ONE stored embedding is accepted under
    /// best-of, but pulled below threshold by `.averageSimilarity`.
    @Test func bestSimilarityAmplifiesImpostorSpikeVersusAverage() {
        // Four poor matches and one lucky spike — the shape of a real
        // stranger-vs-5-embedding-template comparison.
        let template: [[Float]] = [
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1],
        ]
        let probe: [Float] = [1, 0, 0, 0]

        let best = CalibrationEngine.candidateScore(
            probe: probe, template: template, strategy: .bestSimilarity
        )
        let average = CalibrationEngine.candidateScore(
            probe: probe, template: template, strategy: .averageSimilarity
        )

        #expect(best > average)
        #expect(best == 1.0)
        #expect(average <= 0.25)
    }
}
