import Foundation
import XCTest
@testable import KilnCore

/// Tests for the M9.C distilled classifier runner.
///
/// Strategy: drive ``SubprocessDistilledClassifierRunner`` against a
/// shell-script fake launcher that prints canned ``classification`` events
/// on stdout. This exercises the full subprocess + JSON decoding path
/// without any Python or sklearn dependency in CI.
final class DistilledClassifierRunnerTests: XCTestCase {

    private func makeFakeLauncher(
        emit lines: [String],
        exitCode: Int32 = 0
    ) throws -> (TrainerLauncher, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-classify-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("fake-classify.sh")
        // Heredoc-friendly script: echo each canned line, then exit with the
        // requested code. Quoted single-tick prevents shell interpolation.
        let body = """
        #!/bin/bash
        \(lines.map { "echo '\($0)'" }.joined(separator: "\n"))
        exit \(exitCode)
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        let launcher = TrainerLauncher(
            executableURL: script,
            argumentPrefix: [],
            workingDirectory: dir,
            environment: nil
        )
        return (launcher, dir)
    }

    // MARK: - Quality

    func test_quality_classify_returns_scores_in_input_order() async throws {
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"classification","request_id":"r1","kind":"quality","payload":{"score":0.82,"bucket":"keep"}}"#,
            #"{"event":"classification","request_id":"r2","kind":"quality","payload":{"score":0.55,"bucket":"chosen_only"}}"#,
            #"{"event":"classification","request_id":"r3","kind":"quality","payload":{"score":0.21,"bucket":"discard"}}"#,
            #"{"event":"done","stage":"classify","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessDistilledClassifierRunner(
            launcher: launcher,
            qualityArtifactPath: URL(fileURLWithPath: "/tmp/fake-artifact.pkl")
        )
        let rows = [
            ClassifierInputRow(requestID: "r1", text: "voice"),
            ClassifierInputRow(requestID: "r2", text: "midline"),
            ClassifierInputRow(requestID: "r3", text: "boilerplate"),
        ]
        let result = try await runner.classify(rows)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].requestID, "r1")
        XCTAssertEqual(result[0].bucket, .keep)
        XCTAssertEqual(result[0].score, 0.82, accuracy: 1e-9)
        XCTAssertEqual(result[1].bucket, .chosenOnly)
        XCTAssertEqual(result[2].bucket, .discard)
    }

    func test_quality_classify_throws_on_nonzero_exit() async throws {
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"error","code":"adapter_invalid","message":"missing artifact","recoverable":false}"#,
            #"{"event":"done","stage":"classify","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned, exitCode: 1)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessDistilledClassifierRunner(
            launcher: launcher,
            qualityArtifactPath: URL(fileURLWithPath: "/tmp/fake.pkl")
        )
        do {
            _ = try await runner.classify([
                ClassifierInputRow(requestID: "r1", text: "anything")
            ])
            XCTFail("expected sidecarError")
        } catch DistilledClassifierError.sidecarError(let code, _) {
            XCTAssertEqual(code, "adapter_invalid")
        } catch {
            XCTFail("expected sidecarError, got \(error)")
        }
    }

    // MARK: - Style

    func test_style_extract_decodes_descriptors_and_ngrams() async throws {
        // Single-line canned payload — avoid Swift multiline-string interpolation
        // because the suite previously hung when run after sibling tests.
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"classification","request_id":"corpus","kind":"style","payload":{"style_descriptors":{"formality":0.62,"verbosity":0.45,"warmth":0.18,"hedging":0.30,"humor":0.05,"directness":0.74},"distinctive_ngrams":["forgot dog","sunday afternoon","burnt toast"],"style_card_md":"voice header"}}"#,
            #"{"event":"done","stage":"classify","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessDistilledClassifierRunner(
            launcher: launcher,
            qualityArtifactPath: nil
        )
        let result = try await runner.extract([
            ClassifierInputRow(requestID: "corpus", text: "doesn't matter for fake launcher")
        ])
        XCTAssertEqual(result.count, 1)
        let p = result[0]
        XCTAssertEqual(p.requestID, "corpus")
        XCTAssertEqual(p.descriptors.formality, 0.62, accuracy: 1e-9)
        XCTAssertEqual(p.descriptors.directness, 0.74, accuracy: 1e-9)
        XCTAssertEqual(p.distinctiveNgrams, ["forgot dog", "sunday afternoon", "burnt toast"])
        XCTAssertEqual(p.styleCardMarkdown, "voice header")
    }

    func test_classify_throws_missingResults_when_count_lower_than_input() async throws {
        // Sidecar emits only one classification but we asked for two rows.
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
            #"{"event":"classification","request_id":"r1","kind":"quality","payload":{"score":0.5,"bucket":"chosen_only"}}"#,
            #"{"event":"done","stage":"classify","artifact":"stdout","interrupted":false}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessDistilledClassifierRunner(
            launcher: launcher,
            qualityArtifactPath: URL(fileURLWithPath: "/tmp/fake.pkl")
        )
        do {
            _ = try await runner.classify([
                ClassifierInputRow(requestID: "r1", text: "first"),
                ClassifierInputRow(requestID: "r2", text: "second"),
            ])
            XCTFail("expected missingResults")
        } catch DistilledClassifierError.missingResults(let expected, let received) {
            XCTAssertEqual(expected, 2)
            XCTAssertEqual(received, 1)
        } catch {
            XCTFail("expected missingResults, got \(error)")
        }
    }

    func test_quality_classify_throws_when_artifact_path_missing() async throws {
        let canned = [
            #"{"event":"ready","version":"0.1.0","mlx":"0.22.1"}"#,
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = SubprocessDistilledClassifierRunner(
            launcher: launcher,
            qualityArtifactPath: nil
        )
        do {
            _ = try await runner.classify([
                ClassifierInputRow(requestID: "r1", text: "anything")
            ])
            XCTFail("expected launchFailed")
        } catch DistilledClassifierError.launchFailed(let message) {
            XCTAssertTrue(message.contains("artifact"))
        } catch {
            XCTFail("expected launchFailed, got \(error)")
        }
    }

    // MARK: - Concurrent stderr drain regression

    func test_runner_does_not_deadlock_on_large_stderr_burst() async throws {
        // Verifier T3 from PR #15: reading stdout to EOF before stderr
        // would deadlock if the child fills the 64 KB stderr pipe before
        // closing stdout. Concurrent drain (async-let × 2) removes the
        // hazard. Regression test: emit ~80 KB of stderr before stdout.
        let stderrBlast = String(repeating: "x", count: 80 * 1024)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-stderr-blast-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let blastFile = dir.appendingPathComponent("blast.txt")
        try stderrBlast.write(to: blastFile, atomically: true, encoding: .utf8)
        let script = dir.appendingPathComponent("fake-noisy.sh")
        let body = """
        #!/bin/bash
        cat \(blastFile.path) >&2
        echo '{"event":"ready","version":"0.1.0","mlx":"0.22.1"}'
        echo '{"event":"classification","request_id":"r1","kind":"quality","payload":{"score":0.5,"bucket":"chosen_only"}}'
        echo '{"event":"done","stage":"classify","artifact":"stdout","interrupted":false}'
        exit 0
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        let launcher = TrainerLauncher(
            executableURL: script,
            argumentPrefix: [],
            workingDirectory: dir,
            environment: nil
        )
        let runner = SubprocessDistilledClassifierRunner(
            launcher: launcher,
            qualityArtifactPath: URL(fileURLWithPath: "/tmp/fake.pkl")
        )
        // The test fails by hanging if the drain order is wrong — XCTest's
        // per-test timeout (default 60s) catches it.
        let result = try await runner.classify([
            ClassifierInputRow(requestID: "r1", text: "anything")
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].requestID, "r1")
    }

    // MARK: - Cancellation regression (Saturday-audit T2)

    func test_runner_terminates_subprocess_on_outer_task_cancellation() async throws {
        // Spawn a fake script that sleeps far longer than the test
        // budget, send a parent-task cancellation, and assert the
        // runner terminates the child instead of waiting for it.
        // Without the cancellation watcher this test hangs forever
        // (caught by XCTest's per-test timeout).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-cancel-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("fake-slow.sh")
        // 30 s sleep is well above the 5-second test deadline; if the
        // runner does not terminate the child the Task.cancel will
        // resolve before the script's natural exit but the await on
        // .value will still hang waiting for waitUntilExit.
        let body = """
        #!/bin/bash
        echo '{"event":"ready","version":"0.1.0","mlx":"0.22.1"}'
        sleep 30
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        let launcher = TrainerLauncher(
            executableURL: script,
            argumentPrefix: [],
            workingDirectory: dir,
            environment: nil
        )
        let runner = SubprocessDistilledClassifierRunner(
            launcher: launcher,
            qualityArtifactPath: URL(fileURLWithPath: "/tmp/fake.pkl")
        )

        let task = Task {
            try await runner.classify([
                ClassifierInputRow(requestID: "r1", text: "anything")
            ])
        }
        // Give the script time to start, then cancel.
        try await Task.sleep(nanoseconds: 500_000_000)
        task.cancel()
        // Result should resolve quickly (within ~1 s of cancel) rather
        // than waiting 30s for the sleep. Either an error or empty
        // results — both are fine. The point is non-hang.
        let start = Date()
        _ = try? await task.value
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 4.0, "runner did not honour cancellation; took \(elapsed) s")
    }

    // MARK: - Empty input fast path

    func test_classify_returns_empty_for_empty_input_without_launching() async throws {
        // Use a launcher pointing at a non-existent file — if we DID launch
        // it'd fail. Empty input must short-circuit before any process work.
        let launcher = TrainerLauncher(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            argumentPrefix: [],
            workingDirectory: nil,
            environment: nil
        )
        let runner = SubprocessDistilledClassifierRunner(
            launcher: launcher,
            qualityArtifactPath: URL(fileURLWithPath: "/tmp/fake.pkl")
        )
        let qResult = try await runner.classify([])
        XCTAssertEqual(qResult, [])
        let sResult = try await runner.extract([])
        XCTAssertEqual(sResult, [])
    }
}
