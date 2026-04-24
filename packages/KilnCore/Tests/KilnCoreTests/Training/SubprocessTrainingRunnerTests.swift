import XCTest
@testable import KilnCore

/// Opt-in end-to-end smoke. Spawns the real Python sidecar against the
/// in-tree fake trainer (no MLX), asserts we receive the expected event
/// sequence. Guarded by `KILN_RUN_SIDECAR=1` so CI defaults to skip.
final class SubprocessTrainingRunnerTests: XCTestCase {

    private static var shouldRun: Bool {
        ProcessInfo.processInfo.environment["KILN_RUN_SIDECAR"] == "1"
    }

    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url = url.deletingLastPathComponent()
        }
        return url
    }

    private var trainerPackageDir: URL {
        repoRoot.appendingPathComponent("packages/kiln_trainer")
    }

    private var tinyChatMLURL: URL {
        trainerPackageDir.appendingPathComponent("tests/fixtures/tiny_chatml.jsonl")
    }

    func test_trainArgs_contains_required_flags() throws {
        let request = TrainingRequest(
            datasetURL: URL(fileURLWithPath: "/tmp/data.jsonl"),
            runDir: URL(fileURLWithPath: "/tmp/run"),
            model: "test/model",
            seed: 7,
            hyperparameters: Hyperparameters(),
            itersOverride: 42,
            trainerModule: "fake.mod",
            trainerEntry: "main"
        )
        let args = SubprocessTrainingRunner.trainArgs(for: request)

        XCTAssertEqual(args.first, "train")
        XCTAssertTrue(args.contains("--dataset"))
        XCTAssertTrue(args.contains("/tmp/data.jsonl"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("test/model"))
        XCTAssertTrue(args.contains("--run-dir"))
        XCTAssertTrue(args.contains("/tmp/run"))
        XCTAssertTrue(args.contains("--iters"))
        XCTAssertTrue(args.contains("42"))
        XCTAssertTrue(args.contains("--trainer-module"))
        XCTAssertTrue(args.contains("fake.mod"))
        XCTAssertTrue(args.contains("--trainer-entry"))
        XCTAssertTrue(args.contains("main"))
        XCTAssertTrue(args.contains("--seed"))
        XCTAssertTrue(args.contains("7"))
        XCTAssertTrue(args.contains("--save-every"))
    }

    func test_trainArgs_omits_overrides_when_nil() {
        let request = TrainingRequest(
            datasetURL: URL(fileURLWithPath: "/tmp/d.jsonl"),
            runDir: URL(fileURLWithPath: "/tmp/r")
        )
        let args = SubprocessTrainingRunner.trainArgs(for: request)
        XCTAssertFalse(args.contains("--iters"))
        XCTAssertFalse(args.contains("--trainer-module"))
        XCTAssertFalse(args.contains("--trainer-entry"))
    }

    // MARK: - Opt-in subprocess smoke

    func test_smoke_spawns_sidecar_and_yields_events() async throws {
        try XCTSkipUnless(Self.shouldRun, "Set KILN_RUN_SIDECAR=1 to run subprocess smoke tests")

        let tmp = try TestFixtures.makeTempDir(prefix: "kiln-train-smoke")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let runDir = tmp.appendingPathComponent("run")
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        let request = TrainingRequest(
            datasetURL: tinyChatMLURL,
            runDir: runDir,
            model: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            itersOverride: 10,
            trainerModule: "kiln_trainer.tests.fixtures.fake_trainer",
            trainerEntry: "main"
        )
        let runner = SubprocessTrainingRunner(
            launcher: .uvRun(trainerPackageDir: trainerPackageDir)
        )

        var progressCount = 0
        var sawDone = false
        for try await event in runner.runStreaming(request: request) {
            switch event {
            case .progress: progressCount += 1
            case .done: sawDone = true
            default: break
            }
            if sawDone { break }
        }

        XCTAssertGreaterThanOrEqual(progressCount, 5, "expected ≥5 progress events from fake trainer")
        XCTAssertTrue(sawDone, "expected a terminal .done event")
    }
}
