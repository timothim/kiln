import XCTest
import KilnCore
@testable import Kiln

@MainActor
final class TrainModelTests: XCTestCase {

    private func waitForStatus(
        _ model: TrainModel,
        timeout: TimeInterval = 2.0,
        file: StaticString = #file,
        line: UInt = #line,
        predicate: @escaping @MainActor (TrainModel.Status) -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(model.status) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out; observed \(model.status)", file: file, line: line)
    }

    private func makeRequest(
        iters: Int = 40,
        runDir: URL? = nil
    ) -> TrainingRequest {
        let dir = runDir ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kiln-train-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return TrainingRequest(
            datasetURL: URL(fileURLWithPath: "/dev/null"),
            runDir: dir,
            itersOverride: iters
        )
    }

    // MARK: - 1. Idle defaults

    func test_idle_defaults() {
        let model = TrainModel()
        XCTAssertEqual(model.status, .idle)
        XCTAssertNil(model.currentProgress)
        XCTAssertTrue(model.lossHistory.isEmpty)
        XCTAssertNil(model.lastCheckpoint?.iter)
        XCTAssertTrue(model.isWarmingUp)
    }

    // MARK: - 2. Happy path

    func test_happy_path_completes_with_report() async throws {
        let runDir = try TestSupport.makeRunDir()
        let adapterURL = runDir.appendingPathComponent("adapters.safetensors")
        FileManager.default.createFile(atPath: adapterURL.path, contents: Data())

        var events: [TrainingEvent] = [.ready(version: "0.1.0", mlx: "0.22.0")]
        for iter in 1...40 {
            events.append(.progress(TrainingProgress(
                iter: iter,
                loss: max(0.5, 1.5 - 0.02 * Double(iter)),
                tokensPerSec: 900,
                valLoss: iter % 10 == 0 ? 1.0 : nil,
                learningRate: 1e-4
            )))
            if iter % 10 == 0 {
                events.append(.checkpoint(path: adapterURL, iter: iter, best: nil))
            }
        }
        events.append(.done(artifact: adapterURL, interrupted: false))

        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 40, runDir: runDir),
                            stream: TrainEventStream.from(events: events))

        await waitForStatus(model) { status in
            if case .completed = status { return true }
            return false
        }
        guard case .completed(let report) = model.status else {
            return XCTFail("expected .completed, got \(model.status)")
        }
        XCTAssertEqual(report.itersCompleted, 40)
        XCTAssertEqual(report.totalIters, 40)
        XCTAssertFalse(report.interrupted)
        XCTAssertFalse(report.partialCheckpoint)
        XCTAssertEqual(report.adapterURL, adapterURL)
        XCTAssertEqual(model.sidecarVersion, "0.1.0")
        XCTAssertFalse(model.isWarmingUp, "should exit warm-up after iter 20")
        XCTAssertFalse(model.lossHistory.isEmpty)
    }

    // MARK: - 3. Error mid-run

    func test_error_mid_run_maps_to_failed_oom() async {
        let events: [TrainingEvent] = [
            .progress(TrainingProgress(iter: 10, loss: 1.2)),
            .error(.oom(message: "MLX OOM at iter 12; try --max-seq-length 1024"))
        ]
        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 40),
                            stream: TrainEventStream.from(events: events))

        await waitForStatus(model) { status in
            if case .failed(.outOfMemory) = status { return true }
            return false
        }
        guard case .failed(let err) = model.status else { return XCTFail() }
        XCTAssertFalse(err.userFacingMessage.isEmpty)
    }

    // MARK: - 4. Cancel after a checkpoint → partial completion

    func test_cancel_with_checkpoint_becomes_completed_partial() async throws {
        let runDir = try TestSupport.makeRunDir()
        let adapterURL = runDir.appendingPathComponent("adapters.safetensors")
        FileManager.default.createFile(atPath: adapterURL.path, contents: Data())

        // Stream yields 50 iters + checkpoint, then hangs. Cancel injects .done(interrupted=true).
        let events: [TrainingEvent] = (1...50).flatMap { iter -> [TrainingEvent] in
            var rows: [TrainingEvent] = [.progress(TrainingProgress(iter: iter, loss: 1.5 - 0.01 * Double(iter), tokensPerSec: 900))]
            if iter == 50 { rows.append(.checkpoint(path: adapterURL, iter: 50, best: nil)) }
            return rows
        } + [.done(artifact: adapterURL, interrupted: true)]

        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 400, runDir: runDir),
                            stream: TrainEventStream.from(events: events))

        await waitForStatus(model) { status in
            if case .completed = status { return true }
            return false
        }
        guard case .completed(let report) = model.status else {
            return XCTFail("expected .completed, got \(model.status)")
        }
        XCTAssertTrue(report.interrupted)
        XCTAssertTrue(report.partialCheckpoint)
    }

    // MARK: - 5. Cancel before any checkpoint → failed(.cancelled)

    func test_cancel_before_checkpoint_becomes_failed_cancelled() async throws {
        let runDir = try TestSupport.makeRunDir()
        let adapterURL = runDir.appendingPathComponent("adapters.safetensors")
        // Note: deliberately do NOT create the file — sidecar emits done(interrupted=true) with a path
        // that doesn't exist on disk before the first checkpoint.
        let events: [TrainingEvent] = [
            .progress(TrainingProgress(iter: 1, loss: 1.5)),
            .progress(TrainingProgress(iter: 2, loss: 1.48)),
            .done(artifact: adapterURL, interrupted: true)
        ]
        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 400, runDir: runDir),
                            stream: TrainEventStream.from(events: events))

        await waitForStatus(model) { status in
            if case .failed(.cancelled) = status { return true }
            return false
        }
    }

    // MARK: - 6. Cancel on open-ended stream

    func test_cancel_on_openended_stream_transitions_to_failed_cancelled() async {
        let stream = TrainEventStream.openEnded(initial: [
            .progress(TrainingProgress(iter: 1, loss: 1.5, tokensPerSec: 900))
        ])
        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 400), stream: stream)
        await waitForStatus(model) { status in
            if case .running = status { return true }
            return false
        }
        model.cancel()
        switch model.status {
        case .cancelling: break
        default: XCTFail("expected .cancelling, got \(model.status)")
        }
        await waitForStatus(model) { status in
            if case .failed(.cancelled) = status { return true }
            return false
        }
    }

    // MARK: - 7. Loss history is capped

    func test_loss_history_cap_drops_earliest_samples() async {
        let events: [TrainingEvent] = (1...250).map { iter in
            .progress(TrainingProgress(iter: iter, loss: 1.0))
        } + [.done(artifact: URL(fileURLWithPath: "/dev/null"), interrupted: false)]

        let runDir = try! TestSupport.makeRunDir()
        FileManager.default.createFile(atPath: runDir.appendingPathComponent("adapters.safetensors").path, contents: Data())
        // NB: we use /dev/null as artifact here; partialCheckpoint is only set when interrupted=true,
        // so a clean done() with /dev/null still completes — the adapter URL is just a value.

        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 250, runDir: runDir),
                            stream: TrainEventStream.from(events: events))

        await waitForStatus(model) { status in
            if case .completed = status { return true }
            return false
        }
        XCTAssertLessThanOrEqual(model.lossHistory.count, 200)
    }

    // MARK: - 8. ETA prefers sidecar value, falls back to EMA

    func test_eta_uses_sidecar_value_when_present() async {
        let events: [TrainingEvent] = [
            .progress(TrainingProgress(iter: 25, loss: 1.0, tokensPerSec: 900, etaSec: 777))
        ]
        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 400),
                            stream: TrainEventStream.openEnded(initial: events))
        await waitForStatus(model) { _ in model.currentEta != nil }
        XCTAssertEqual(model.currentEta ?? -1, 777, accuracy: 0.001)
        model.cancel() // stop the open-ended stream
    }

    func test_eta_falls_back_to_local_ema_when_sidecar_omits() async {
        let events: [TrainingEvent] = [
            .progress(TrainingProgress(iter: 25, loss: 1.0, tokensPerSec: 900))
        ]
        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 400),
                            stream: TrainEventStream.openEnded(initial: events))
        await waitForStatus(model) { _ in model.currentEta != nil }
        XCTAssertGreaterThan(model.currentEta ?? -1, 0)
        model.cancel()
    }

    // MARK: - 9. Training Advisor (PR #23)

    func test_advisor_observation_event_appends_to_observations() async {
        let events: [TrainingEvent] = [
            .ready(version: "0.1.0", mlx: "0.22.1"),
            .progress(TrainingProgress(iter: 5, loss: 1.5, tokensPerSec: 900)),
            .advisorObservation(iter: 5, content: "Voice is stabilizing.", modelID: "claude-opus-4-7"),
            .progress(TrainingProgress(iter: 10, loss: 1.3, tokensPerSec: 900)),
            .advisorObservation(iter: 10, content: "Loss plateauing.", modelID: "claude-opus-4-7"),
        ]
        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 100),
                            stream: TrainEventStream.openEnded(initial: events))
        await waitForStatus(model) { _ in model.advisorObservations.count >= 2 }
        XCTAssertEqual(model.advisorObservations.count, 2)
        XCTAssertEqual(model.advisorObservations[0].iter, 5)
        XCTAssertEqual(model.advisorObservations[0].content, "Voice is stabilizing.")
        XCTAssertEqual(model.advisorObservations[1].modelID, "claude-opus-4-7")
        model.cancel()
    }

    func test_reset_clears_advisor_observations() async {
        let events: [TrainingEvent] = [
            .advisorObservation(iter: 5, content: "first", modelID: "claude-opus-4-7"),
            .advisorObservation(iter: 10, content: "second", modelID: "claude-opus-4-7"),
        ]
        let model = TrainModel()
        model.testing_start(request: makeRequest(iters: 100),
                            stream: TrainEventStream.openEnded(initial: events))
        await waitForStatus(model) { _ in model.advisorObservations.count >= 2 }
        model.reset()
        XCTAssertTrue(model.advisorObservations.isEmpty)
        XCTAssertEqual(model.status, .idle)
    }
}

/// Local support helpers so we don't pull in anything from KilnCoreTests.
enum TestSupport {
    static func makeRunDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kiln-train-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
