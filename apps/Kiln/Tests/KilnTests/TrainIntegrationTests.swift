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

    // MARK: - M6: .sample events populate the GrowingModelPanel state

    func test_sample_events_populate_growing_model_panel() async throws {
        let datasetURL = tempDir.appendingPathComponent("train.jsonl")
        FileManager.default.createFile(atPath: datasetURL.path, contents: Data("{}\n".utf8))
        let adapterURL = tempDir.appendingPathComponent("adapters.safetensors")
        FileManager.default.createFile(atPath: adapterURL.path, contents: Data())

        // Build: ready → 5 progresses → round-1 samples (3) → 15 more progresses
        // → round-2 samples (3, different completions) → unknown-id sample → done.
        var events: [TrainingEvent] = [.ready(version: "0.1.0", mlx: "0.22.0")]
        for iter in 1...5 {
            events.append(.progress(TrainingProgress(
                iter: iter,
                loss: 1.5 - 0.05 * Double(iter),
                tokensPerSec: 900
            )))
        }
        events.append(.sample(TrainingSample(iter: 10, promptID: "week_focus",     completion: "Draft 1: focus.")))
        events.append(.sample(TrainingSample(iter: 10, promptID: "birthday_msg",   completion: "Draft 1: birthday.")))
        events.append(.sample(TrainingSample(iter: 10, promptID: "perfect_sunday", completion: "Draft 1: sunday.")))
        for iter in 6...20 {
            events.append(.progress(TrainingProgress(
                iter: iter,
                loss: 1.2 - 0.02 * Double(iter),
                tokensPerSec: 900
            )))
        }
        events.append(.sample(TrainingSample(iter: 20, promptID: "week_focus",     completion: "Ship the thing.")))
        events.append(.sample(TrainingSample(iter: 20, promptID: "birthday_msg",   completion: "Happy birthday.")))
        events.append(.sample(TrainingSample(iter: 20, promptID: "perfect_sunday", completion: "Coffee, walk, nap.")))
        events.append(.sample(TrainingSample(iter: 20, promptID: "unknown_id",     completion: "ignored")))
        events.append(.done(artifact: adapterURL, interrupted: false))

        let runner = FakeTrainingRunner(events: events)
        let app = AppModel(trainingRunnerFactory: { runner })

        var project = Project(name: "GrowingModel", stage: .training)
        project.preparedDatasetURL = datasetURL
        app.projects = [project]
        app.selectedProjectID = project.id

        app.startTraining(projectID: project.id)
        guard let trainModel = app.trainModel else {
            return XCTFail("AppModel did not create a TrainModel")
        }
        await waitForStatus(trainModel) { status in
            if case .completed = status { return true }
            return false
        }

        // Seeded three prompt cards.
        XCTAssertEqual(trainModel.growingModelSamples.count, 3)

        // Latest-wins aggregation — round-2 completions visible.
        let index = Dictionary(uniqueKeysWithValues:
            GrowingModelPrompts.defaults.enumerated().map { ($0.element.id, $0.offset) })
        if let weekIdx = index["week_focus"] {
            XCTAssertEqual(trainModel.growingModelSamples[weekIdx].currentResponse, "Ship the thing.")
        } else {
            XCTFail("week_focus missing from prompt index")
        }
        if let bdayIdx = index["birthday_msg"] {
            XCTAssertEqual(trainModel.growingModelSamples[bdayIdx].currentResponse, "Happy birthday.")
        } else {
            XCTFail("birthday_msg missing from prompt index")
        }
        if let sunIdx = index["perfect_sunday"] {
            XCTAssertEqual(trainModel.growingModelSamples[sunIdx].currentResponse, "Coffee, walk, nap.")
        } else {
            XCTFail("perfect_sunday missing from prompt index")
        }

        // Final state reached .completed.
        XCTAssertEqual(trainModel.growingModelState, .completed)

        // Unknown promptID was tolerated — no extra row, no crash, none of the
        // three cards' responses equal "ignored".
        XCTAssertFalse(trainModel.growingModelSamples.contains { $0.currentResponse == "ignored" })
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

/// Captures the ``TrainingRequest`` argument so tests can assert on the
/// flag values that flowed in from ``AppModel.startTraining``. Used by
/// the post-audit C4 regression test.
private final class CapturingTrainingRunner: TrainingRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: TrainingRequest?

    func runStreaming(request: TrainingRequest) -> AsyncThrowingStream<TrainingEvent, Error> {
        lock.lock(); captured = request; lock.unlock()
        return AsyncThrowingStream { continuation in
            // Yield a clean done so the TrainModel doesn't sit running.
            let url = request.runDir.appendingPathComponent("adapters.safetensors")
            FileManager.default.createFile(atPath: url.path, contents: Data())
            continuation.yield(.checkpoint(path: url, iter: 1, best: nil))
            continuation.yield(.done(artifact: url, interrupted: false))
            continuation.finish()
        }
    }

    var capturedRequest: TrainingRequest? {
        lock.lock(); defer { lock.unlock() }
        return captured
    }
}

// MARK: - C4 regression: AppModel reads the canonical training-advisor key

@MainActor
final class AppModelAdvisorToggleTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kiln-c4-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: CloudFeaturesSettingsKeys.trainingAdvisorEnabled)
        UserDefaults.standard.removeObject(forKey: CloudFeaturesSettingsKeys.voiceCoachLocalMode)
        UserDefaults.standard.removeObject(forKey: "trainingAdvisorEnabled")
        UserDefaults.standard.removeObject(forKey: "voiceCoachLocalMode")
    }

    private func startWithDefaults(canonical: Bool, local: Bool) -> CapturingTrainingRunner {
        // Make sure no stale legacy literals interfere.
        UserDefaults.standard.removeObject(forKey: "trainingAdvisorEnabled")
        UserDefaults.standard.removeObject(forKey: "voiceCoachLocalMode")
        UserDefaults.standard.set(canonical, forKey: CloudFeaturesSettingsKeys.trainingAdvisorEnabled)
        UserDefaults.standard.set(local, forKey: CloudFeaturesSettingsKeys.voiceCoachLocalMode)

        let datasetURL = tempDir.appendingPathComponent("train.jsonl")
        FileManager.default.createFile(atPath: datasetURL.path, contents: Data("{}\n".utf8))

        let runner = CapturingTrainingRunner()
        let app = AppModel(trainingRunnerFactory: { runner })
        var project = Project(name: "AdvisorToggle", stage: .training)
        project.preparedDatasetURL = datasetURL
        app.projects = [project]
        app.selectedProjectID = project.id
        app.startTraining(projectID: project.id)
        return runner
    }

    func test_canonical_advisor_key_true_sets_enableAdvisor_on_request() {
        let runner = startWithDefaults(canonical: true, local: false)
        guard let req = runner.capturedRequest else {
            return XCTFail("AppModel did not call runStreaming on the runner")
        }
        XCTAssertTrue(req.enableAdvisor, "canonical key set to true should flip enableAdvisor")
        XCTAssertEqual(req.advisorMode, "cloud")
    }

    func test_canonical_advisor_key_false_leaves_enableAdvisor_off() {
        let runner = startWithDefaults(canonical: false, local: false)
        guard let req = runner.capturedRequest else {
            return XCTFail("AppModel did not call runStreaming")
        }
        XCTAssertFalse(req.enableAdvisor)
    }

    func test_legacy_literal_key_does_not_flip_advisor() {
        // The pre-fix bug: a legacy ``trainingAdvisorEnabled`` literal in
        // UserDefaults must NOT enable the advisor. Only the canonical
        // dotted key counts.
        UserDefaults.standard.removeObject(forKey: CloudFeaturesSettingsKeys.trainingAdvisorEnabled)
        UserDefaults.standard.set(true, forKey: "trainingAdvisorEnabled")
        defer { UserDefaults.standard.removeObject(forKey: "trainingAdvisorEnabled") }

        let datasetURL = tempDir.appendingPathComponent("train.jsonl")
        FileManager.default.createFile(atPath: datasetURL.path, contents: Data("{}\n".utf8))
        let runner = CapturingTrainingRunner()
        let app = AppModel(trainingRunnerFactory: { runner })
        var project = Project(name: "LegacyKey", stage: .training)
        project.preparedDatasetURL = datasetURL
        app.projects = [project]
        app.selectedProjectID = project.id
        app.startTraining(projectID: project.id)
        guard let req = runner.capturedRequest else {
            return XCTFail("AppModel did not call runStreaming")
        }
        XCTAssertFalse(req.enableAdvisor, "legacy literal must not control the advisor")
    }

    func test_local_mode_toggle_flips_advisor_mode_to_local() {
        let runner = startWithDefaults(canonical: true, local: true)
        guard let req = runner.capturedRequest else {
            return XCTFail("AppModel did not call runStreaming")
        }
        XCTAssertTrue(req.enableAdvisor)
        XCTAssertEqual(req.advisorMode, "local")
    }
}
