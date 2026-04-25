import Foundation

/// Public-facing types for Kiln's distilled classifiers (M9.C).
///
/// Three classifiers ship in the Python sidecar — quality, preference,
/// style — each invoked via ``kiln_trainer classify`` and consumed here
/// through ``QualityClassifierRunner`` / ``StyleExtractorRunner``.
///
/// The sidecar emits one ``classification`` event per scored row plus a
/// ``done(stage="classify")``. The structs below mirror the wire schema
/// (see ``docs/ipc/protocol.md`` §3.8).

// MARK: - Quality

/// Quality bucket assigned to a corpus chunk.
///
/// Cutoffs come from ``KEEP_THRESHOLD`` / ``CHOSEN_ONLY_THRESHOLD`` in
/// ``kiln_trainer.classifiers.quality``: ≥ 0.70 → keep, [0.40, 0.70) →
/// chosen-only (used as DPO chosen, never as prompt), < 0.40 → discard.
public enum QualityBucket: String, Sendable, Hashable, Codable {
    case keep
    case chosenOnly = "chosen_only"
    case discard
}

/// One row's quality assessment — the raw probability and the routing decision.
public struct QualityScore: Sendable, Hashable, Codable {
    public let requestID: String
    public let score: Double
    public let bucket: QualityBucket

    public init(requestID: String, score: Double, bucket: QualityBucket) {
        self.requestID = requestID
        self.score = score
        self.bucket = bucket
    }
}

// MARK: - Style

/// Six-axis stylometric profile of a corpus. Values are clamped to [0, 1].
public struct StyleDescriptors: Sendable, Hashable, Codable {
    public let formality: Double
    public let verbosity: Double
    public let warmth: Double
    public let hedging: Double
    public let humor: Double
    public let directness: Double

    public init(
        formality: Double,
        verbosity: Double,
        warmth: Double,
        hedging: Double,
        humor: Double,
        directness: Double
    ) {
        self.formality = formality
        self.verbosity = verbosity
        self.warmth = warmth
        self.hedging = hedging
        self.humor = humor
        self.directness = directness
    }
}

/// One corpus → one style profile. ``distinctiveNgrams`` are TF-IDF
/// distinctive against an inline corporate-English background; the
/// markdown card is a deterministic template fill.
public struct DistilledStyleProfile: Sendable, Hashable, Codable {
    public let requestID: String
    public let descriptors: StyleDescriptors
    public let distinctiveNgrams: [String]
    public let styleCardMarkdown: String

    public init(
        requestID: String,
        descriptors: StyleDescriptors,
        distinctiveNgrams: [String],
        styleCardMarkdown: String
    ) {
        self.requestID = requestID
        self.descriptors = descriptors
        self.distinctiveNgrams = distinctiveNgrams
        self.styleCardMarkdown = styleCardMarkdown
    }
}

// MARK: - Errors

public enum DistilledClassifierError: Error, Equatable, Sendable {
    /// The sidecar exited non-zero. ``code`` is the process exit status.
    case unexpectedExit(code: Int32, stderrTail: String)
    /// The sidecar emitted an ``error`` event we surfaced verbatim.
    case sidecarError(code: String, message: String)
    /// Process never started — bad path, permissions, etc.
    case launchFailed(message: String)
    /// We received fewer ``classification`` events than ``texts.count``.
    case missingResults(expected: Int, received: Int)
}
