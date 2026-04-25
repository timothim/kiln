import Foundation
import KilnCore

/// Maps the M9.C distilled-classifier output into the UI-layer
/// ``StyleSignature`` struct that ``StyleSignatureCardView`` renders.
///
/// The card view's struct (``StyleSignature``) was authored before the
/// distilled-classifier output shape existed — the two diverged on
/// purpose so the UI could be polished independently. This presenter
/// is the one place where they meet: take a ``DistilledStyleProfile``
/// (from ``StyleExtractorRunner.extract(_:)``) plus optional sentence-
/// length stats, produce a ``StyleSignature``.
///
/// All field derivations are deterministic and explained in-line so a
/// future reader can adjust the heuristics without re-reading the M9
/// plan. None of this calls back into the sidecar — the runner does
/// that — so the presenter is cheap and trivially testable in isolation.
enum StyleSignaturePresenter {

    /// Build a UI signature from a distilled profile.
    ///
    /// - Parameters:
    ///   - profile: One ``DistilledStyleProfile`` from the runner.
    ///   - userLabel: Display name shown in the card header.
    ///   - sentenceLengthBuckets: Optional histogram (counts per bucket,
    ///     ascending). Pass ``nil`` to fall back to a flat-distribution
    ///     placeholder — only used when the corpus stats aren't
    ///     available yet (e.g., live partial-training previews).
    static func makeSignature(
        from profile: DistilledStyleProfile,
        userLabel: String,
        sentenceLengthBuckets: [Int]? = nil
    ) -> StyleSignature {
        StyleSignature(
            userLabel: userLabel,
            summary: summary(from: profile.descriptors),
            signaturePhrases: signaturePhrases(from: profile.distinctiveNgrams),
            syntacticPatterns: syntacticPatterns(from: profile.descriptors, ngrams: profile.distinctiveNgrams),
            sentenceLengthBuckets: sentenceLengthBuckets ?? Self.fallbackBuckets,
            register: register(from: profile.descriptors)
        )
    }

    // MARK: - Field derivations

    /// Two-clause summary built from the strongest descriptor pair.
    /// ``"Direct, terse. Reserved warmth, decisive cadence."`` and so on.
    static func summary(from descriptors: StyleDescriptors) -> String {
        let pairs: [(String, Double)] = [
            ("formal", descriptors.formality),
            ("casual", 1 - descriptors.formality),
            ("verbose", descriptors.verbosity),
            ("terse", 1 - descriptors.verbosity),
            ("warm", descriptors.warmth),
            ("reserved", 1 - descriptors.warmth),
            ("hedging", descriptors.hedging),
            ("decisive", 1 - descriptors.hedging),
            ("playful", descriptors.humor),
            ("earnest", 1 - descriptors.humor),
            ("direct", descriptors.directness),
            ("elliptical", 1 - descriptors.directness),
        ]
        let strongest = pairs.sorted { $0.1 > $1.1 }
        let lead = strongest.prefix(2).map { $0.0 }.joined(separator: ", ").capitalized + "."
        let secondary = strongest.dropFirst(2).prefix(2).map { $0.0 }.joined(separator: ", ").capitalized + "."
        return "\(lead) \(secondary)"
    }

    /// Map distinctive n-grams to weighted phrases for the word-cloud
    /// renderer. Weights decay linearly from 1.0 down to 0.4 by rank
    /// — matches the previous mock distribution and avoids any phrase
    /// shrinking to invisibility in the word cloud.
    static func signaturePhrases(from ngrams: [String]) -> [SignaturePhrase] {
        guard !ngrams.isEmpty else { return [] }
        let n = ngrams.count
        return ngrams.enumerated().map { idx, text in
            let rank = Double(idx)
            let weight = 1.0 - (rank / Double(max(n - 1, 1))) * 0.6
            return SignaturePhrase(text: text, weight: weight)
        }
    }

    /// Synthesize a small list of syntactic-pattern strings from
    /// descriptor signals + the most distinctive n-grams. The card
    /// shows up to ~5 of these so the Voice section has something to
    /// say beyond the descriptor labels themselves.
    static func syntacticPatterns(
        from descriptors: StyleDescriptors,
        ngrams: [String]
    ) -> [String] {
        var out: [String] = []
        if descriptors.directness >= 0.6 && descriptors.verbosity <= 0.4 {
            out.append("Short declarative leads")
        }
        if descriptors.hedging >= 0.5 {
            out.append("Frequent hedge clauses (\"maybe\", \"probably\")")
        }
        if descriptors.formality <= 0.3 {
            out.append("Contractions and informalities")
        }
        if descriptors.warmth >= 0.4 {
            out.append("Direct second-person address")
        }
        if let firstNgram = ngrams.first {
            out.append("Recurring phrase: \"\(firstNgram)\"")
        }
        if out.isEmpty {
            out.append("Mixed register, no dominant pattern")
        }
        return Array(out.prefix(5))
    }

    /// Map the formality/hedging descriptors onto one of four registers.
    /// The bucketing follows the existing card's enum vocabulary.
    static func register(from descriptors: StyleDescriptors) -> Register {
        if descriptors.formality >= 0.65 && descriptors.hedging >= 0.5 {
            return .technical
        }
        if descriptors.formality >= 0.65 {
            return .formal
        }
        if descriptors.warmth >= 0.45 || descriptors.humor >= 0.30 {
            return .casual
        }
        // Low-formality, low-warmth, low-humor reads as deliberate,
        // image-driven prose — call it poetic. The card's poetic register
        // is the catch-all for "voice that isn't easily labeled".
        return .poetic
    }

    // MARK: - Fallbacks

    /// Placeholder bucket histogram used when the caller hasn't produced
    /// real sentence-length stats yet. Skewed toward shorter sentences
    /// so the histogram reads as "voice-bearing" rather than flat.
    private static let fallbackBuckets: [Int] = [12, 28, 22, 14, 8, 4]
}
