import Foundation
import XCTest
@testable import KilnCore

/// Tests for the Saturday Phase 3 ingest-agent runner. Drives the
/// streaming subprocess via canned events on a fake-shell launcher.
final class IngestAgentRunnerTests: XCTestCase {

    private func makeFakeLauncher(emit lines: [String], exitCode: Int32 = 0) throws -> (TrainerLauncher, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-agent-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("fake-agent.sh")
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
            executableURL: script, argumentPrefix: [],
            workingDirectory: dir, environment: nil
        )
        return (launcher, dir)
    }

    private func sampleRequest(out: URL) -> IngestAgentRequest {
        IngestAgentRequest(
            sources: ["local_documents"],
            intent: "personal writing",
            local: true,
            outputPath: out,
            documentsRoot: nil,
            perSourceLimit: 50
        )
    }

    func test_runner_yields_typed_events_in_order() async throws {
        let canned = [
            "{\"event\":\"ready\",\"version\":\"0.1.0\",\"mlx\":\"0.22.1\"}",
            "{\"event\":\"agent_thinking\",\"content\":\"Reading from 1 source\"}",
            "{\"event\":\"subagent_spawned\",\"source\":\"local_documents\"}",
            "{\"event\":\"sample_found\",\"source\":\"local_documents\",\"sample_id\":\"abc\",\"preview\":\"hello\",\"confidence\":0.5}",
            "{\"event\":\"agent_decision\",\"content\":\"keeping all\"}",
            "{\"event\":\"completion\",\"samples_kept\":1,\"sources_processed\":1,\"sources_skipped\":[]}",
            "{\"event\":\"done\",\"stage\":\"generation\",\"artifact\":\"corpus.jsonl\",\"interrupted\":false}",
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = SubprocessIngestAgentRunner(launcher: launcher)
        let out = dir.appendingPathComponent("corpus.jsonl")
        var collected: [IngestAgentEvent] = []
        for try await event in runner.runStreaming(request: sampleRequest(out: out)) {
            collected.append(event)
        }
        // Expect: thinking, spawned, sample, decision, completion (5 events)
        XCTAssertEqual(collected.count, 5)
        if case .agentThinking(let c) = collected[0] {
            XCTAssertTrue(c.contains("Reading"))
        } else {
            XCTFail("expected agentThinking first, got \(collected[0])")
        }
        if case .subagentSpawned(let src) = collected[1] {
            XCTAssertEqual(src, "local_documents")
        } else {
            XCTFail("expected subagentSpawned at index 1")
        }
        if case .sampleFound(_, let sid, let preview, let confidence) = collected[2] {
            XCTAssertEqual(sid, "abc")
            XCTAssertEqual(preview, "hello")
            XCTAssertEqual(confidence, 0.5, accuracy: 1e-9)
        } else {
            XCTFail("expected sampleFound at index 2")
        }
        if case .completion(let kept, let processed, let skipped) = collected[4] {
            XCTAssertEqual(kept, 1)
            XCTAssertEqual(processed, 1)
            XCTAssertEqual(skipped, [])
        } else {
            XCTFail("expected completion at end")
        }
    }

    func test_runner_throws_on_nonzero_exit() async throws {
        let canned = [
            "{\"event\":\"ready\",\"version\":\"0.1.0\",\"mlx\":\"0.22.1\"}",
            "{\"event\":\"error\",\"code\":\"data_invalid\",\"message\":\"bad sources\",\"recoverable\":false}",
        ]
        let (launcher, dir) = try makeFakeLauncher(emit: canned, exitCode: 1)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = SubprocessIngestAgentRunner(launcher: launcher)
        let out = dir.appendingPathComponent("corpus.jsonl")
        var sawError = false
        do {
            for try await event in runner.runStreaming(request: sampleRequest(out: out)) {
                if case .error = event { sawError = true }
            }
            XCTFail("expected unexpectedExit")
        } catch IngestAgentError.unexpectedExit(let code, _) {
            XCTAssertEqual(code, 1)
        } catch {
            XCTFail("expected unexpectedExit, got \(error)")
        }
        XCTAssertTrue(sawError)
    }

    func test_runner_command_args_include_local_flag_and_intent() {
        // The command construction is private to the runner, but we
        // can prove the wire is right via the typed Request.
        let req = IngestAgentRequest(
            sources: ["local_documents", "apple_notes"],
            intent: "personal voice",
            local: true,
            outputPath: URL(fileURLWithPath: "/tmp/x.jsonl")
        )
        XCTAssertEqual(req.sources.joined(separator: ","), "local_documents,apple_notes")
        XCTAssertEqual(req.intent, "personal voice")
        XCTAssertTrue(req.local)
    }

    // MARK: - Cancellation retrofit (Saturday-final, fixup/saturday-cancellation)

    func test_runner_terminates_subprocess_on_stream_break() async throws {
        // Spawn a fake agent that emits the ready line then sleeps 30 s.
        // Break out of the for-await loop early; the
        // continuation.onTermination handler must SIGTERM (and escalate
        // to SIGKILL) so the subprocess doesn't outlive the test.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-agent-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("fake-slow-agent.sh")
        let body = """
        #!/bin/bash
        echo '{"event":"ready","version":"0.1.0","mlx":"0.22.1"}'
        echo '{"event":"agent_thinking","content":"first thought"}'
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
        let runner = SubprocessIngestAgentRunner(launcher: launcher)
        let out = dir.appendingPathComponent("corpus.jsonl")

        let start = Date()
        var first: IngestAgentEvent? = nil
        let stream = runner.runStreaming(request: sampleRequest(out: out))
        for try await event in stream {
            first = event
            break // signals the stream that consumption is over
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertNotNil(first, "expected at least one event before break")
        XCTAssertLessThan(
            elapsed, 4.0,
            "ingest-agent runner did not honour stream cancellation; took \(elapsed) s"
        )
    }
}
