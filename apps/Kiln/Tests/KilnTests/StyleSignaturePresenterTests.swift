import XCTest
@testable import Kiln
import KilnCore

/// Tests for the M9.C presenter that maps a ``DistilledStyleProfile``
/// (from the runner) onto the existing UI ``StyleSignature`` struct.
final class StyleSignaturePresenterTests: XCTestCase {

    private func makeProfile(
        formality: Double = 0.5,
        verbosity: Double = 0.4,
        warmth: Double = 0.2,
        hedging: Double = 0.2,
        humor: Double = 0.1,
        directness: Double = 0.7,
        ngrams: [String] = ["forgot dog", "sunday afternoon"]
    ) -> DistilledStyleProfile {
        DistilledStyleProfile(
            requestID: "fixture",
            descriptors: StyleDescriptors(
                formality: formality,
                verbosity: verbosity,
                warmth: warmth,
                hedging: hedging,
                humor: humor,
                directness: directness
            ),
            distinctiveNgrams: ngrams,
            styleCardMarkdown: "## Voice\n- direct.\n\n## Tells\n- forgot dog"
        )
    }

    func test_signaturePhrases_assigns_decreasing_weights() {
        let profile = makeProfile(ngrams: ["alpha", "beta", "gamma"])
        let signature = StyleSignaturePresenter.makeSignature(from: profile, userLabel: "Tim")
        XCTAssertEqual(signature.signaturePhrases.count, 3)
        XCTAssertEqual(signature.signaturePhrases[0].text, "alpha")
        // Weights must monotonically decrease.
        let weights = signature.signaturePhrases.map { $0.weight }
        XCTAssertGreaterThan(weights[0], weights[1])
        XCTAssertGreaterThan(weights[1], weights[2])
        // First weight is the canonical 1.0 anchor.
        XCTAssertEqual(weights[0], 1.0, accuracy: 1e-9)
        // Last weight is bounded by 0.4 floor.
        XCTAssertGreaterThanOrEqual(weights.last ?? 0, 0.4)
    }

    func test_register_picks_technical_for_high_formality_high_hedging() {
        let profile = makeProfile(formality: 0.8, hedging: 0.6)
        let sig = StyleSignaturePresenter.makeSignature(from: profile, userLabel: "Pat")
        XCTAssertEqual(sig.register, .technical)
    }

    func test_register_picks_casual_for_warm_corpus() {
        let profile = makeProfile(formality: 0.3, warmth: 0.6)
        let sig = StyleSignaturePresenter.makeSignature(from: profile, userLabel: "Pat")
        XCTAssertEqual(sig.register, .casual)
    }

    func test_register_falls_back_to_poetic_for_neutral_corpus() {
        let profile = makeProfile(formality: 0.3, warmth: 0.1, humor: 0.05, hedging: 0.1)
        let sig = StyleSignaturePresenter.makeSignature(from: profile, userLabel: "Pat")
        XCTAssertEqual(sig.register, .poetic)
    }

    func test_syntactic_patterns_emit_for_short_declarative_voice() {
        // Direct + terse should fire "Short declarative leads".
        let profile = makeProfile(verbosity: 0.2, directness: 0.8)
        let sig = StyleSignaturePresenter.makeSignature(from: profile, userLabel: "Pat")
        XCTAssertTrue(sig.syntacticPatterns.contains("Short declarative leads"))
        // The first n-gram surfaces as a "Recurring phrase" hint.
        XCTAssertTrue(sig.syntacticPatterns.contains(where: { $0.contains("forgot dog") }))
    }

    func test_summary_reflects_strongest_descriptors() {
        // High directness, low verbosity, low warmth, low humor →
        // "Direct, terse" should appear in the lead clause.
        let profile = makeProfile(formality: 0.5, verbosity: 0.1, warmth: 0.1, humor: 0.05, directness: 0.9)
        let sig = StyleSignaturePresenter.makeSignature(from: profile, userLabel: "Pat")
        XCTAssertTrue(sig.summary.lowercased().contains("direct"))
        XCTAssertTrue(sig.summary.lowercased().contains("terse"))
    }

    func test_default_buckets_used_when_caller_omits_them() {
        let profile = makeProfile()
        let sig = StyleSignaturePresenter.makeSignature(from: profile, userLabel: "Pat")
        XCTAssertEqual(sig.sentenceLengthBuckets.count, 6)
        XCTAssertGreaterThan(sig.sentenceLengthBuckets.reduce(0, +), 0)
    }

    func test_caller_buckets_pass_through_unchanged() {
        let profile = makeProfile()
        let custom = [10, 20, 5, 1, 0, 0]
        let sig = StyleSignaturePresenter.makeSignature(
            from: profile,
            userLabel: "Pat",
            sentenceLengthBuckets: custom
        )
        XCTAssertEqual(sig.sentenceLengthBuckets, custom)
    }
}
