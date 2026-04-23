import XCTest
import KilnCore
@testable import Kiln

@MainActor
final class PrepareModelTests: XCTestCase {

    private func waitForStatus(
        _ model: PrepareModel,
        timeout: TimeInterval = 2.0,
        file: StaticString = #file,
        line: UInt = #line,
        predicate: @escaping @MainActor (PrepareModel.Status) -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(model.status) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for status; observed \(model.status)", file: file, line: line)
    }

    func test_idle_state_is_default() {
        let model = PrepareModel()
        XCTAssertEqual(model.status, .idle)
        XCTAssertEqual(model.counts.filesDiscovered, 0)
        XCTAssertEqual(model.counts.chunksAfterQuality, 0)
        XCTAssertEqual(model.stageProgress, 0)
        XCTAssertEqual(model.overallProgress, 0)
        XCTAssertTrue(model.liveSamples.isEmpty)
    }

    func test_running_state_updates_counts_on_progress_event() async {
        var countsSnapshot = RunningCounts()
        countsSnapshot.filesDiscovered = 12
        countsSnapshot.filesParsed = 10
        let events: [IngestEvent] = [
            .stageStarted(.discovery),
            .runningCounts(countsSnapshot),
            .stageFinished(.discovery),
            .stageStarted(.parsing),
            .progress(IngestProgress(stage: .parsing, done: 10, total: 12))
        ]
        let model = PrepareModel()
        model.testing_start(stream: PreparedEventStream.from(events: events))

        await waitForStatus(model) { status in
            if case .failed = status { return true }
            if case .running = status {
                return model.counts.filesParsed == 10
            }
            return false
        }
        XCTAssertEqual(model.counts.filesDiscovered, 12)
        XCTAssertEqual(model.counts.filesParsed, 10)
    }

    func test_sample_carousel_rolling_window_keeps_last_3() async {
        let samples = (0..<5).map { i in
            ChunkPreview(sourcePath: "/tmp/file-\(i).md", kind: .text,
                         assistantSnippet: "snippet-\(i)", userPromptSnippet: "")
        }
        let events: [IngestEvent] = samples.map { .sample($0) }
        let model = PrepareModel()
        model.testing_start(stream: PreparedEventStream.from(events: events))

        await waitForStatus(model) { _ in model.liveSamples.count >= 3 }
        XCTAssertEqual(model.liveSamples.count, 3)
        XCTAssertEqual(model.liveSamples.map(\.id), Array(samples.suffix(3).map(\.id)))
    }

    func test_completed_state_carries_report() async {
        var report = IngestReport()
        report.chunksAfterQuality = 42
        report.trainCount = 38
        report.evalCount = 4
        let events: [IngestEvent] = [.completed(report)]

        let model = PrepareModel()
        model.testing_start(stream: PreparedEventStream.from(events: events))

        await waitForStatus(model) { status in
            if case .completed = status { return true }
            return false
        }
        if case .completed(let gotReport) = model.status {
            XCTAssertEqual(gotReport.chunksAfterQuality, 42)
            XCTAssertEqual(gotReport.trainCount, 38)
        } else {
            XCTFail("expected .completed, got \(model.status)")
        }
    }

    func test_failed_state_on_ingest_error() async {
        let stream = PreparedEventStream.failing(
            with: IngestError.directoryNotFound(URL(fileURLWithPath: "/does-not-exist"))
        )
        let model = PrepareModel()
        model.testing_start(stream: stream)

        await waitForStatus(model) { status in
            if case .failed(.directoryNotFound) = status { return true }
            return false
        }
    }

    func test_cancellation_transitions_to_failed_cancelled() async throws {
        // Stream that yields a stageStarted, then blocks forever so cancel can bite.
        let stream = AsyncThrowingStream<IngestEvent, Error> { continuation in
            continuation.yield(.stageStarted(.parsing))
            // Intentionally never finish — the Task.cancel() should terminate iteration.
        }
        let model = PrepareModel()
        model.testing_start(stream: stream)

        await waitForStatus(model) { status in
            if case .running = status { return true }
            return false
        }
        // Force-drive the status machine: cancel requires .running.
        model.cancel()
        XCTAssertEqual(model.status, .cancelling)

        await waitForStatus(model) { status in
            if case .failed(.cancelled) = status { return true }
            return false
        }
    }
}
