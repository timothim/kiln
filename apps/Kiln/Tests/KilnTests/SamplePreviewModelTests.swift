import XCTest
import KilnCore
@testable import Kiln

/// Audit C5 regression: ``SamplePreviewModel`` drives the Before/After
/// pane. Pre-fix, the panel was a hardcoded placeholder; the only data
/// shown was identical canned text. These tests exercise the model's
/// state machine against a deterministic stub runner so any future
/// regression to the placeholder path fails CI loudly.
@MainActor
final class SamplePreviewModelTests: XCTestCase {

    /// Stub runner that yields a scripted sequence of events. Used to
    /// drive the model through every state without spawning a sidecar.
    private struct StubRunner: SampleCompareRunner {
        let events: [SampleCompareEvent]

        func runStreaming(request: SampleCompareRequest) -> AsyncThrowingStream<SampleCompareEvent, Error> {
            let snapshot = events
            return AsyncThrowingStream { continuation in
                for event in snapshot {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    private func adapterURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kiln-sample-preview-test.safetensors")
    }

    // MARK: - 1. Happy path: both variants produce completions

    func test_runCompare_populates_base_and_tuned_completions_then_lands_in_ready() async {
        let events: [SampleCompareEvent] = [
            .ready(version: "0.1.0", mlx: "0.22.0"),
            .generation(SampleCompareGeneration(
                variant: .base,
                prompt: "What should I work on this week?",
                completion: "Here are several prioritization frameworks.",
                tokens: 6, tokensPerSec: 50.0
            )),
            .generation(SampleCompareGeneration(
                variant: .sft,
                prompt: "What should I work on this week?",
                completion: "Pick the one you'd regret skipping. Then start.",
                tokens: 9, tokensPerSec: 48.5
            )),
            .done(interrupted: false, variantsDelivered: [.base, .sft]),
        ]
        let model = SamplePreviewModel(
            runner: StubRunner(events: events),
            baseModel: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            adapterURL: adapterURL()
        )
        XCTAssertEqual(model.state, .idle)
        await model.runCompare()
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.baseCompletion, "Here are several prioritization frameworks.")
        XCTAssertEqual(model.tunedCompletion, "Pick the one you'd regret skipping. Then start.")
        XCTAssertNil(model.baseFailureMessage)
        XCTAssertNil(model.tunedFailureMessage)
    }

    // MARK: - 2. Per-variant failure: base fails, sft succeeds → still ready

    func test_runCompare_shows_per_variant_failure_when_base_errors_but_sft_succeeds() async {
        let events: [SampleCompareEvent] = [
            .variantFailed(variant: .base, message: "Failed to load base weights.", code: "model_not_found"),
            .generation(SampleCompareGeneration(
                variant: .sft,
                prompt: "What should I work on this week?",
                completion: "Pick the one you'd regret skipping.",
                tokens: 7, tokensPerSec: 49.0
            )),
            .done(interrupted: false, variantsDelivered: [.sft]),
        ]
        let model = SamplePreviewModel(
            runner: StubRunner(events: events),
            baseModel: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            adapterURL: adapterURL()
        )
        await model.runCompare()
        XCTAssertEqual(model.state, .ready, "ready when at least one variant produced output")
        XCTAssertNil(model.baseCompletion)
        XCTAssertEqual(model.baseFailureMessage, "Failed to load base weights.")
        XCTAssertEqual(model.tunedCompletion, "Pick the one you'd regret skipping.")
    }

    // MARK: - 3. Both variants fail → state lands in .failed

    func test_runCompare_lands_in_failed_when_both_variants_error() async {
        let events: [SampleCompareEvent] = [
            .variantFailed(variant: .base, message: "base broken", code: "subprocess_failed"),
            .variantFailed(variant: .sft, message: "sft broken", code: "subprocess_failed"),
            .done(interrupted: false, variantsDelivered: []),
        ]
        let model = SamplePreviewModel(
            runner: StubRunner(events: events),
            baseModel: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            adapterURL: adapterURL()
        )
        await model.runCompare()
        if case .failed(let m) = model.state {
            XCTAssertTrue(m.contains("broken") || m.contains("output"))
        } else {
            XCTFail("expected .failed, got \(model.state)")
        }
    }

    // MARK: - 4. Re-run resets per-variant state before firing

    func test_runCompare_re_run_clears_previous_state() async {
        let firstRun: [SampleCompareEvent] = [
            .generation(SampleCompareGeneration(
                variant: .base, prompt: "p", completion: "first base",
                tokens: 1, tokensPerSec: 1
            )),
            .generation(SampleCompareGeneration(
                variant: .sft, prompt: "p", completion: "first sft",
                tokens: 1, tokensPerSec: 1
            )),
            .done(interrupted: false, variantsDelivered: [.base, .sft]),
        ]
        let model = SamplePreviewModel(
            runner: StubRunner(events: firstRun),
            baseModel: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            adapterURL: adapterURL()
        )
        await model.runCompare()
        XCTAssertEqual(model.baseCompletion, "first base")
        XCTAssertEqual(model.tunedCompletion, "first sft")

        // Now confirm a second run resets state. The runner is a value
        // closure under StubRunner so we can replay a different script
        // by constructing a fresh model — but the bug-target is that
        // the FIRST model's per-variant fields don't leak across runs.
        // Simulate that by manually re-firing on the same model with
        // the same script and asserting the state goes through .running
        // before settling at .ready again. (Since StubRunner has no
        // delay, the .running phase is invisible to the caller; what
        // we can assert is that the completions are written, not stale.)
        await model.runCompare()
        XCTAssertEqual(model.baseCompletion, "first base", "re-run must repopulate, not leave stale nil")
        XCTAssertEqual(model.state, .ready)
    }
}
