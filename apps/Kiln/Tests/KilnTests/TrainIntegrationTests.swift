import XCTest
import KilnCore
@testable import Kiln

/// End-to-end wiring: AppModel → TrainModel → TrainingRunner → UI state.
/// A fake runner yields a canned event sequence and we assert that the
/// project, train model, and AppModel all end in the expected state
/// after start → completed → continueFromTraining.
@MainActor
final class TrainIntegrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempDir = base.appendingPathComponent("kiln-train-integ-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func waitForStatus(
        _ model: TrainModel,
        timeout: TimeInterval = 3.0,
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

    // MARK: - Happy path — press Teach → Completed → Continue → project.stage = .complete

    func test_press_teach_runs_to_completion_and_continue_moves_to_complete() async throws {
        // Build a fake adapter file so the runner's "artifact" path exists.
        let adapterURL = tempDir.appendingPathComponent("adapters.safetensors")
        FileManager.default.createFile(atPath: adapterURL.path, contents: Data())

        // Canned sequence: 40 progress events, checkpoints every 10, clean done.
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

        let runner = FakeTrainingRunner(events: events)
        let app = AppModel(trainingRunnerFactory: { runner })

        // Simulate what continueToTraining would have done: a project sitting
        // at .training with a prepared dataset URL.
        let datasetURL = tempDir.appendingPathComponent("train.jsonl")
        FileManager.default.createFile(atPath: datasetURL.path, contents: Data("{}\n".utf8))
        var project = Project(name: "Integ", stage: .training)
        project.preparedDatasetURL = datasetURL
        app.projects = [project]
        app.selectedProjectID = project.id

        // Press Teach.
        app.startTraining(projectID: project.id)

        guard let trainModel = app.trainModel else {
            return XCTFail("AppModel did not create a TrainModel")
        }

        await waitForStatus(trainModel) { status in
            if case .completed = status { return true }
            return false
        }

        guard case .completed(let report) = trainModel.status else {
            return XCTFail("expected .completed, got \(trainModel.status)")
        }
        XCTAssertEqual(report.itersCompleted, 40)
        XCTAssertFalse(report.interrupted)
        XCTAssertFalse(report.partialCheckpoint)
        XCTAssertEqual(report.adapterURL, adapterURL)

        // Pressing Continue moves the project to .complete and clears trainModel.
        app.continueFromTraining(projectID: project.id)
        XCTAssertEqual(app.projects.first?.stage, .complete)
        XCTAssertNotNil(app.projects.first?.trainingReport)
        XCTAssertNotNil(app.projects.first?.lastTrained)
        XCTAssertNil(app.trainModel)
    }

    // MARK: - Error mid-run — UI surfaces DisplayError.outOfMemory

    func test_sidecar_oom_surfaces_as_failed_outofmemory() async throws {
        let datasetURL = tempDir.appendingPathComponent("train.jsonl")
        FileManager.default.createFile(atPath: datasetURL.path, contents: Data("{}\n".utf8))

        let events: [TrainingEvent] = [
            .progress(TrainingProgress(iter: 10, loss: 1.2)),
            .error(.oom(message: "MLX OOM at iter 12; try --max-seq-length 1024"))
        ]
        let runner = FakeTrainingRunner(events: events)
        let app = AppModel(trainingRunnerFactory: { runner })

        var project = Project(name: "OOM", stage: .training)
        project.preparedDatasetURL = datasetURL
        app.projects = [project]
        app.selectedProjectID = project.id

        app.startTraining(projectID: project.id)

        guard let trainModel = app.trainModel else {
            return XCTFail("no TrainModel created")
        }
        await waitForStatus(trainModel) { status in
            if case .failed(.outOfMemory) = status { return true }
            return false
        }
        // Project stays at .training so the Try-again path is available.
        XCTAssertEqual(app.projects.first?.stage, .training)
    }

    // MARK: - startTraining is a no-op without a prepared dataset

    func test_start_training_without_prepared_dataset_is_noop() {
        let runner = FakeTrainingRunner(events: [])
        let app = AppModel(trainingRunnerFactory: { runner })
        let project = Project(name: "Empty", stage: .training)   // no preparedDatasetURL
        app.projects = [project]
        app.selectedProjectID = project.id

        app.startTraining(projectID: project.id)
        XCTAssertNil(app.trainModel)
    }
}

/// Minimal TrainingRunner that replays a pre-baked event array over an
/// AsyncThrowingStream. No subprocesses; no timing. Deterministic.
private final class FakeTrainingRunner: TrainingRunner, @unchecked Sendable {
    private let events: [TrainingEvent]

    init(events: [TrainingEvent]) {
        self.events = events
    }

    func runStreaming(request: TrainingRequest) -> AsyncThrowingStream<TrainingEvent, Error> {
        let events = self.events
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
