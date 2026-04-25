import Foundation
import XCTest
@testable import KilnCore

/// Tests for the Saturday Phase 4 Deep Curation runner.
final class DeepCurationRunnerTests: XCTestCase {

    private func makeFakeLauncher(emit lines: [String], exitCode: Int32 = 0) throws -> (TrainerLauncher, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-curate-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("fake-curate.sh")
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
        return (
            TrainerLauncher(
                executableURL: script, argumentPrefix: [],
                workingDirectory: dir, environment: nil
            ),
            dir
        )
    }

    private func sampleRequest(in dir: URL) -> DeepCurationRequest {
        DeepCurationRequest(
            corpusPath: dir.appendingPathComponent("c.jsonl"),
            outputPath: dir.appendingPathComponent("out.jsonl"),
            reportPath: dir.appendingPathComponent("r.json"),
            dryRun: true
        )
    }

    func test_runner_yields_thinking_progress_completion_in_order() async throws {
        let canned = [
            "{\"event\":\"ready\",\"version\":\"0.1.0\",\"mlx\":\"0.22.1\"}",
            "{\"event\":\"agent_thinking\",\"content\":\"Loaded corpus\"}",
            "{\"event\":\"agent_progress\",\"samples_reviewed\":100,\"removals\":12,\"flags\":4}",
            "{\"event\":\"agent_completion\",\"samples_kept\":84,\"samples_removed\":12,\"samples_flagged\":4,\"report_path\":\"/tmp/r.json\",\"curated_path\":\"/tmp/out.jsonl\"}",
            "{\"event\":\"done\",\"stage\":\"generation\",\"artifact\":\"/tmp/out.jsonl\",\"interrupted\":false}",
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = SubprocessDeepCurationRunner(launcher: launcher)
        var collected: [DeepCurationEvent] = []
        for try await event in runner.runStreaming(request: sampleRequest(in: dir), apiKey: nil) {
            collected.append(event)
        }
        XCTAssertEqual(collected.count, 3)
        if case .thinking(let content) = collected[0] {
            XCTAssertTrue(content.contains("corpus"))
        } else { XCTFail("expected thinking first") }
        if case .progress(let reviewed, let removals, let flags) = collected[1] {
            XCTAssertEqual(reviewed, 100)
            XCTAssertEqual(removals, 12)
            XCTAssertEqual(flags, 4)
        } else { XCTFail("expected progress at index 1") }
        if case .completion(let kept, let removed, let flagged, _, _) = collected[2] {
            XCTAssertEqual(kept, 84)
            XCTAssertEqual(removed, 12)
            XCTAssertEqual(flagged, 4)
        } else { XCTFail("expected completion at end") }
    }

    func test_runner_yields_error_event_then_throws_on_nonzero_exit() async throws {
        let canned = [
            "{\"event\":\"ready\",\"version\":\"0.1.0\",\"mlx\":\"0.22.1\"}",
            "{\"event\":\"error\",\"code\":\"data_invalid\",\"message\":\"corpus file not found\",\"recoverable\":false}",
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned, exitCode: 1)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = SubprocessDeepCurationRunner(launcher: launcher)
        var sawError = false
        do {
            for try await event in runner.runStreaming(request: sampleRequest(in: dir), apiKey: nil) {
                if case .error = event { sawError = true }
            }
            XCTFail("expected unexpectedExit throw")
        } catch DeepCurationError.unexpectedExit(let code, _) {
            XCTAssertEqual(code, 1)
        } catch {
            XCTFail("expected unexpectedExit, got \(error)")
        }
        XCTAssertTrue(sawError)
    }

    func test_dry_run_arg_is_threaded_through_the_request() {
        let req = DeepCurationRequest(
            corpusPath: URL(fileURLWithPath: "/tmp/c.jsonl"),
            outputPath: URL(fileURLWithPath: "/tmp/out.jsonl"),
            reportPath: URL(fileURLWithPath: "/tmp/r.json"),
            dryRun: true
        )
        XCTAssertTrue(req.dryRun)
        XCTAssertEqual(req.corpusPath.lastPathComponent, "c.jsonl")
    }

    // MARK: - Cancellation retrofit (Saturday-final, fixup/saturday-cancellation)

    func test_runner_terminates_subprocess_on_stream_break() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-curate-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("fake-slow-curate.sh")
        let body = """
        #!/bin/bash
        echo '{"event":"ready","version":"0.1.0","mlx":"0.22.1"}'
        echo '{"event":"agent_thinking","content":"deploying agent"}'
        sleep 30
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        let launcher = TrainerLauncher(
            executableURL: script, argumentPrefix: [],
            workingDirectory: dir, environment: nil
        )
        let runner = SubprocessDeepCurationRunner(launcher: launcher)

        let start = Date()
        var first: DeepCurationEvent? = nil
        for try await event in runner.runStreaming(request: sampleRequest(in: dir), apiKey: nil) {
            first = event
            break
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertNotNil(first)
        XCTAssertLessThan(elapsed, 4.0,
            "deep-curation runner did not honour stream cancellation; took \(elapsed) s")
    }
}
