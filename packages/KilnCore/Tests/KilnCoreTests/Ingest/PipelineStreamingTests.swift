import XCTest
@testable import KilnCore

private final class CancelBox: @unchecked Sendable {
    var error: Error?
}

private final class EventCountBox: @unchecked Sendable {
    var count: Int = 0
}

final class PipelineStreamingTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestFixtures.makeTempDir(prefix: "kiln-pipeline-stream")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func collect(
        _ stream: AsyncThrowingStream<IngestEvent, Error>
    ) async throws -> [IngestEvent] {
        var events: [IngestEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func test_streaming_emits_stage_boundaries_in_order() async throws {
        let out = tempDir.appendingPathComponent("out")
        let stream = IngestPipeline().runStreaming(
            sourceDirectory: TestFixtures.sampleCorpusURL,
            outputDirectory: out
        )
        let events = try await collect(stream)

        var stageOrder: [IngestStage] = []
        for event in events {
            if case .stageStarted(let stage) = event { stageOrder.append(stage) }
        }
        XCTAssertEqual(stageOrder, [.discovery, .parsing, .dedup, .quality, .writing])

        var finishedOrder: [IngestStage] = []
        for event in events {
            if case .stageFinished(let stage) = event { finishedOrder.append(stage) }
        }
        XCTAssertEqual(finishedOrder, [.discovery, .parsing, .dedup, .quality, .writing])

        if case .completed = events.last {
        } else {
            XCTFail("last event must be .completed, got \(String(describing: events.last))")
        }
    }

    func test_streaming_completed_report_matches_run_result() async throws {
        let outA = tempDir.appendingPathComponent("a")
        let outB = tempDir.appendingPathComponent("b")
        let pipeline = IngestPipeline()

        let reportA = try await pipeline.run(
            sourceDirectory: TestFixtures.sampleCorpusURL,
            outputDirectory: outA
        )

        var reportB: IngestReport?
        let stream = pipeline.runStreaming(
            sourceDirectory: TestFixtures.sampleCorpusURL,
            outputDirectory: outB
        )
        for try await event in stream {
            if case .completed(let r) = event { reportB = r }
        }

        let unwrappedB = try XCTUnwrap(reportB)
        XCTAssertEqual(reportA.filesDiscovered, unwrappedB.filesDiscovered)
        XCTAssertEqual(reportA.filesParsed, unwrappedB.filesParsed)
        XCTAssertEqual(reportA.chunksBeforeDedup, unwrappedB.chunksBeforeDedup)
        XCTAssertEqual(reportA.chunksAfterExactDedup, unwrappedB.chunksAfterExactDedup)
        XCTAssertEqual(reportA.chunksAfterMinHashDedup, unwrappedB.chunksAfterMinHashDedup)
        XCTAssertEqual(reportA.chunksAfterQuality, unwrappedB.chunksAfterQuality)
        XCTAssertEqual(reportA.trainCount, unwrappedB.trainCount)
        XCTAssertEqual(reportA.evalCount, unwrappedB.evalCount)
        XCTAssertEqual(reportA.softRejectedCount, unwrappedB.softRejectedCount)
        XCTAssertEqual(reportA.hardRejectedCount, unwrappedB.hardRejectedCount)
        XCTAssertEqual(reportA.qualityBreakdown, unwrappedB.qualityBreakdown)
    }

    func test_streaming_respects_cancellation() async throws {
        let src = tempDir.appendingPathComponent("big-src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let body = String(repeating: "This paragraph has enough words to pass the minimum chunk length threshold and avoid being skipped as too short content. ", count: 8)
        for i in 0..<5000 {
            let url = src.appendingPathComponent("file-\(i).md")
            try (body + "Line \(i).").data(using: .utf8)?.write(to: url)
        }
        let out = tempDir.appendingPathComponent("out")
        let pipeline = IngestPipeline()

        let completed = expectation(description: "task completes")
        let eventCountBox = EventCountBox()
        let sawCompletedBox = CancelBox()
        let task = Task<Void, Never> {
            do {
                for try await event in pipeline.runStreaming(
                    sourceDirectory: src,
                    outputDirectory: out
                ) {
                    eventCountBox.count += 1
                    if case .completed = event {
                        sawCompletedBox.error = NSError(domain: "completed", code: 0)
                    }
                }
            } catch {
                // ignored — we only care that the producer stopped
            }
            completed.fulfill()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let eventsAtCancel = eventCountBox.count
        task.cancel()
        await fulfillment(of: [completed], timeout: 10.0)
        let eventsAfterCancel = eventCountBox.count - eventsAtCancel
        XCTAssertTrue(task.isCancelled, "task.isCancelled must be true after cancel()")
        XCTAssertNil(sawCompletedBox.error, "consumer saw .completed after cancel — producer didn't stop")
        XCTAssertLessThan(eventsAfterCancel, 50, "consumer processed \(eventsAfterCancel) events after cancel; producer didn't honor iterator teardown")
    }

    func test_streaming_emits_sample_previews() async throws {
        let out = tempDir.appendingPathComponent("out")
        let stream = IngestPipeline().runStreaming(
            sourceDirectory: TestFixtures.sampleCorpusURL,
            outputDirectory: out,
            sampleEvery: 1
        )
        var sampleCount = 0
        var completedChunksAfterQuality = 0
        for try await event in stream {
            switch event {
            case .sample:
                sampleCount += 1
            case .completed(let report):
                completedChunksAfterQuality = report.chunksAfterQuality
            default:
                break
            }
        }
        XCTAssertGreaterThan(sampleCount, 0, "expected at least one sample preview")
        XCTAssertLessThanOrEqual(sampleCount, completedChunksAfterQuality)
    }

    func test_streaming_running_counts_monotonic() async throws {
        let out = tempDir.appendingPathComponent("out")
        let stream = IngestPipeline().runStreaming(
            sourceDirectory: TestFixtures.sampleCorpusURL,
            outputDirectory: out
        )

        var previous = RunningCounts()
        for try await event in stream {
            if case .runningCounts(let c) = event {
                XCTAssertGreaterThanOrEqual(c.filesDiscovered, previous.filesDiscovered)
                XCTAssertGreaterThanOrEqual(c.filesParsed, previous.filesParsed)
                XCTAssertGreaterThanOrEqual(c.filesSkipped, previous.filesSkipped)
                XCTAssertGreaterThanOrEqual(c.chunksBeforeDedup, previous.chunksBeforeDedup)
                XCTAssertGreaterThanOrEqual(c.chunksAfterExactDedup, previous.chunksAfterExactDedup)
                XCTAssertGreaterThanOrEqual(c.chunksAfterMinHashDedup, previous.chunksAfterMinHashDedup)
                XCTAssertGreaterThanOrEqual(c.chunksAfterQuality, previous.chunksAfterQuality)
                XCTAssertGreaterThanOrEqual(c.softRejected.total, previous.softRejected.total)
                XCTAssertGreaterThanOrEqual(c.hardRejected.total, previous.hardRejected.total)
                previous = c
            }
        }
    }
}
