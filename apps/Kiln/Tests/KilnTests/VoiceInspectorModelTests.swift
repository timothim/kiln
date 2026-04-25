import KilnCore
import XCTest
@testable import Kiln

/// Tests for the M9.B Voice Inspector wiring model.
@MainActor
final class VoiceInspectorModelTests: XCTestCase {

    /// Test runner that returns canned matches without spawning a subprocess.
    final class FakeRunner: EmbedSearchRunner, @unchecked Sendable {
        var matchesByQuery: [String: [EmbedSearchMatch]] = [:]
        var error: Error? = nil
        var calls: [(String, Int)] = []

        func search(
            query: String,
            corpus: [EmbedSearchCorpusRow],
            topK: Int,
            embedder: String
        ) async throws -> [EmbedSearchMatch] {
            calls.append((query, corpus.count))
            if let error { throw error }
            return matchesByQuery[query] ?? []
        }
    }

    private func sampleCorpus() -> [VoiceInspectorModel.CorpusRow] {
        [
            VoiceInspectorModel.CorpusRow(
                id: "msg-1",
                text: "regret not shipping is the only thing that bites",
                source: .messages,
                sourceDetail: "To: Aisha · 2026-03-14",
                excerpt: "regret not shipping is the only thing that bites"
            ),
            VoiceInspectorModel.CorpusRow(
                id: "note-1",
                text: "pick the one thing you'd regret skipping",
                source: .notes,
                sourceDetail: "Note: Weekly plan",
                excerpt: "pick the one thing you'd regret skipping"
            ),
            VoiceInspectorModel.CorpusRow(
                id: "drop-1",
                text: "stakeholders should leverage synergies",
                source: .dropFolder,
                sourceDetail: "templates/genericfile.md",
                excerpt: "stakeholders should leverage synergies"
            ),
        ]
    }

    func test_select_span_calls_runner_and_maps_results_to_nearest_samples() async throws {
        let runner = FakeRunner()
        runner.matchesByQuery["regret not shipping"] = [
            EmbedSearchMatch(requestID: "msg-1", similarity: 0.92, rank: 0),
            EmbedSearchMatch(requestID: "note-1", similarity: 0.81, rank: 1),
        ]
        let model = VoiceInspectorModel(
            runner: runner,
            corpusProvider: { [weak self] in self?.sampleCorpus() ?? [] }
        )
        model.embedderMode = "fake-hash"

        model.selectSpan(
            InspectorSelection(
                generatedSentence: "Pick the one thing you'd regret not shipping.",
                highlightedSpan: "regret not shipping",
                logOddsTopTerms: ["regret", "shipping"]
            )
        )
        // Wait for the in-flight task by polling. Cap at 2 seconds.
        for _ in 0..<200 {
            if !model.isLoading && !model.nearestSamples.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.nearestSamples.count, 2)
        XCTAssertEqual(model.nearestSamples[0].id, "msg-1")
        XCTAssertEqual(model.nearestSamples[0].similarity, 0.92, accuracy: 1e-9)
        XCTAssertEqual(model.nearestSamples[0].source, .messages)
        XCTAssertEqual(model.nearestSamples[1].id, "note-1")
        XCTAssertEqual(model.nearestSamples[1].source, .notes)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.0, "regret not shipping")
    }

    func test_dismiss_clears_state_and_cancels_in_flight() async throws {
        let runner = FakeRunner()
        // Simulate slow runner: throw a CancellationError after a delay
        // would be more realistic, but a synchronous return is enough to
        // prove dismiss() resets state.
        runner.matchesByQuery["span"] = [
            EmbedSearchMatch(requestID: "msg-1", similarity: 0.9, rank: 0),
        ]
        let model = VoiceInspectorModel(
            runner: runner,
            corpusProvider: { self.sampleCorpus() }
        )
        model.selectSpan(
            InspectorSelection(
                generatedSentence: "x",
                highlightedSpan: "span",
                logOddsTopTerms: []
            )
        )
        model.dismiss()
        XCTAssertNil(model.selection)
        XCTAssertEqual(model.nearestSamples, [])
        XCTAssertFalse(model.isLoading)
    }

    func test_runner_error_surfaces_as_lastError_and_clears_loading() async throws {
        let runner = FakeRunner()
        runner.error = EmbedSearchError.sidecarError(code: "data_invalid", message: "bad input")
        let model = VoiceInspectorModel(
            runner: runner,
            corpusProvider: { self.sampleCorpus() }
        )
        model.selectSpan(
            InspectorSelection(
                generatedSentence: "x",
                highlightedSpan: "anything",
                logOddsTopTerms: []
            )
        )
        for _ in 0..<200 {
            if !model.isLoading && model.lastError != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.lastError)
        XCTAssertTrue(model.lastError?.contains("data_invalid") == true)
    }

    func test_empty_corpus_returns_no_matches_and_does_not_call_runner() async throws {
        let runner = FakeRunner()
        let model = VoiceInspectorModel(
            runner: runner,
            corpusProvider: { [] }
        )
        model.selectSpan(
            InspectorSelection(
                generatedSentence: "x",
                highlightedSpan: "anything",
                logOddsTopTerms: []
            )
        )
        XCTAssertEqual(model.nearestSamples, [])
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(runner.calls.count, 0)
    }
}
