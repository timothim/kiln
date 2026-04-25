import Foundation
import OSLog

/// Optional fourth gate after the rule-based quality stage in the
/// ingest pipeline (M9.C wiring). Takes a list of chunks that already
/// survived format/dedup/length, scores them with the distilled quality
/// classifier, and returns:
///
/// - ``keep``: chunks routed to the SFT train set as-is.
/// - ``chosenOnly``: chunks held back for DPO "chosen-only" feedstock
///   (they're not bad enough to throw away but not strong enough to
///   teach voice from on their own).
/// - ``discard``: chunks dropped before training.
///
/// **Default-off-on-failure.** If no ``QualityClassifierRunner`` is
/// configured, or the runner errors, the gate returns every chunk in
/// ``keep`` and zero in the other buckets. The pipeline never refuses
/// to ship because the classifier is missing — the gate is additive,
/// not gating.
public struct ClassifierQualityGate: Sendable {
    public let runner: QualityClassifierRunner?
    /// OSLog channel for the gate. Saturday audit M7: gate degradations
    /// (runner nil, runner threw, count mismatch) now log a warning so
    /// silent fall-throughs are visible in Console.app rather than
    /// only via the absence of nonzero ``classifierBuckets``.
    private static let log = Logger(subsystem: "dev.kiln.core", category: "classifier-gate")

    public init(runner: QualityClassifierRunner?) {
        self.runner = runner
    }

    public struct Routing: Sendable, Hashable {
        public let keep: [ClassifierInputRow]
        public let chosenOnly: [ClassifierInputRow]
        public let discard: [ClassifierInputRow]
        /// True when the classifier successfully scored every input
        /// chunk. False when the gate degraded to a no-op (runner nil,
        /// runner threw, or count mismatch). The pipeline signals
        /// "gate didn't run" to the UI by leaving
        /// ``IngestReport.classifierBuckets`` at the zero default —
        /// see ``writeBackTo(_:)`` below.
        public let didRun: Bool
        public let counts: ClassifierBucketCounts

        public init(
            keep: [ClassifierInputRow],
            chosenOnly: [ClassifierInputRow],
            discard: [ClassifierInputRow],
            didRun: Bool
        ) {
            self.keep = keep
            self.chosenOnly = chosenOnly
            self.discard = discard
            self.didRun = didRun
            self.counts = didRun ? ClassifierBucketCounts(
                keep: keep.count,
                chosenOnly: chosenOnly.count,
                discard: discard.count
            ) : ClassifierBucketCounts()
        }

        /// Update ``report``'s post-classifier fields from this routing.
        /// Idempotent. Called by the pipeline after ``route(_:)``.
        public func writeBackTo(_ report: inout IngestReport) {
            report.classifierBuckets = counts
            // The "Voice-passed" funnel ticker shows ``keep`` size
            // when the gate ran, otherwise mirrors ``chunksAfterQuality``
            // so downstream code that reads either field gets the same
            // pre-gate count.
            report.chunksAfterClassifierQuality = didRun
                ? counts.keep
                : report.chunksAfterQuality
        }
    }

    /// Score every chunk and route it. Returns a degraded "all-keep"
    /// routing (``didRun = false``) if the runner is nil or throws.
    public func route(_ chunks: [ClassifierInputRow]) async -> Routing {
        guard let runner else {
            Self.log.warning("classifier gate degraded: runner not configured (\(chunks.count, privacy: .public) chunks routed all-keep)")
            return Routing(keep: chunks, chosenOnly: [], discard: [], didRun: false)
        }
        do {
            let scored = try await runner.classify(chunks)
            guard scored.count == chunks.count else {
                Self.log.warning("classifier gate degraded: runner returned \(scored.count, privacy: .public) of \(chunks.count, privacy: .public) expected scores; routing all-keep")
                return Routing(keep: chunks, chosenOnly: [], discard: [], didRun: false)
            }
            let scoreByID = Dictionary(
                scored.map { ($0.requestID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var keep: [ClassifierInputRow] = []
            var chosenOnly: [ClassifierInputRow] = []
            var discard: [ClassifierInputRow] = []
            for row in chunks {
                guard let s = scoreByID[row.requestID] else {
                    keep.append(row)
                    continue
                }
                switch s.bucket {
                case .keep: keep.append(row)
                case .chosenOnly: chosenOnly.append(row)
                case .discard: discard.append(row)
                }
            }
            return Routing(keep: keep, chosenOnly: chosenOnly, discard: discard, didRun: true)
        } catch {
            Self.log.warning("classifier gate degraded: runner threw \(String(describing: error), privacy: .public); routing all-keep")
            return Routing(keep: chunks, chosenOnly: [], discard: [], didRun: false)
        }
    }
}
