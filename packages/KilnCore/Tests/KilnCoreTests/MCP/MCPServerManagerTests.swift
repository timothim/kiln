import Foundation
import XCTest
@testable import KilnCore

/// Tests for the Saturday Phase 2 MCP server manager. The
/// long-running subprocess is hard to integration-test in CI, so the
/// suite focuses on lifecycle correctness and the config-snippet
/// generation that's the user-facing artifact.
final class MCPServerManagerTests: XCTestCase {

    private func makeFakeLauncher() throws -> (TrainerLauncher, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-mcp-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("fake-mcp.sh")
        // Long-running fake: read stdin and never exit until SIGTERM'd.
        let body = """
        #!/bin/bash
        # Print the same startup line as the real server so integration
        # callers can sniff it.
        echo 'kiln-voice mcp server starting (voice=test)' >&2
        # Block on stdin so the parent can SIGTERM us cleanly.
        while read line; do :; done
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

    func test_start_then_stop_lifecycle() throws {
        let (launcher, dir) = try makeFakeLauncher()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = MCPServerManager(launcher: launcher)

        let status = try manager.start(voiceName: "kiln-test")
        guard case .running(let voiceName, let snippet) = status else {
            return XCTFail("expected .running, got \(status)")
        }
        XCTAssertEqual(voiceName, "kiln-test")
        XCTAssertTrue(snippet.contains("kiln-voice"))
        XCTAssertTrue(snippet.contains("mcp-serve"))
        XCTAssertTrue(snippet.contains("kiln-test"))

        manager.stop()
        if case .stopped = manager.status {
            // expected
        } else {
            XCTFail("expected .stopped, got \(manager.status)")
        }
    }

    func test_start_is_idempotent_returns_running_status() throws {
        let (launcher, dir) = try makeFakeLauncher()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = MCPServerManager(launcher: launcher)

        _ = try manager.start(voiceName: "kiln-once")
        let secondCall = try manager.start(voiceName: "kiln-twice-ignored")
        // Second call should return the same running status — voice
        // names don't dynamically swap on a re-start.
        if case .running(let voiceName, _) = secondCall {
            XCTAssertEqual(voiceName, "kiln-once")
        } else {
            XCTFail("expected idempotent .running")
        }
        manager.stop()
    }

    func test_stop_when_already_stopped_is_safe() {
        let launcher = TrainerLauncher(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            argumentPrefix: [],
            workingDirectory: nil,
            environment: nil
        )
        let manager = MCPServerManager(launcher: launcher)
        manager.stop() // No prior start.
        if case .stopped = manager.status {
            // expected
        } else {
            XCTFail("stopped → stopped should be a no-op")
        }
    }

    func test_config_snippet_is_valid_json_with_mcpServers_key() throws {
        let snippet = MCPServerManager.configSnippet(
            voiceName: "kiln-tim",
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            argumentPrefix: ["uv", "run", "python", "-m", "kiln_trainer"],
            workingDirectory: URL(fileURLWithPath: "/tmp/kiln")
        )
        let data = snippet.data(using: .utf8)!
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let servers = try XCTUnwrap(parsed["mcpServers"] as? [String: Any])
        let kiln = try XCTUnwrap(servers["kiln-voice"] as? [String: Any])
        let args = try XCTUnwrap(kiln["args"] as? [String])
        XCTAssertTrue(args.contains("mcp-serve"))
        XCTAssertTrue(args.contains("kiln-tim"))
        XCTAssertEqual(kiln["command"] as? String, "/usr/bin/env")
        XCTAssertEqual(kiln["cwd"] as? String, "/tmp/kiln")
    }

    // MARK: - Cancellation retrofit (Saturday-final, fixup/saturday-cancellation)

    func test_stop_escalates_to_sigkill_when_child_ignores_sigterm() throws {
        // Trap SIGTERM in the fake child so it survives the SIGTERM
        // grace window. ``stop(graceSeconds: 0.5)`` must escalate to
        // SIGKILL; without that escalation this test hangs forever.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-mcp-sigkill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("ignore-sigterm.sh")
        let body = """
        #!/bin/bash
        trap '' TERM
        echo 'fake mcp ignoring SIGTERM' >&2
        while true; do sleep 1; done
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
        let manager = MCPServerManager(launcher: launcher)

        _ = try manager.start(voiceName: "kiln-sigkill-test")
        let start = Date()
        manager.stop(graceSeconds: 0.5)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.5, "stop() did not escalate to SIGKILL within budget; took \(elapsed) s")
        if case .stopped = manager.status {
            // expected — kernel reaped the SIGKILL'd child
        } else {
            XCTFail("expected .stopped after SIGKILL, got \(manager.status)")
        }
    }

    func test_deinit_safety_net_terminates_running_subprocess() throws {
        // Verifies that dropping a manager while running doesn't leak
        // the ``mcp-serve`` child. We capture the pid before deinit and
        // assert the process is gone afterwards. ``kill(pid, 0)`` returns
        // 0 if the process exists, ESRCH otherwise.
        let (launcher, dir) = try makeFakeLauncher()
        defer { try? FileManager.default.removeItem(at: dir) }

        var pid: pid_t = 0
        do {
            let manager = MCPServerManager(launcher: launcher)
            _ = try manager.start(voiceName: "kiln-deinit-test")
            // Reach into the manager just to grab the pid for the
            // post-deinit reachability probe.
            pid = manager.processIdentifierForTesting
            XCTAssertGreaterThan(pid, 0)
        } // manager goes out of scope here → deinit fires
        // Give the OS a beat to reap the child after deinit.
        Thread.sleep(forTimeInterval: 0.7)
        let alive = (kill(pid, 0) == 0)
        XCTAssertFalse(alive, "MCPServerManager deinit leaked subprocess pid=\(pid)")
    }

    func test_launch_failure_reflects_in_status() {
        let launcher = TrainerLauncher(
            executableURL: URL(fileURLWithPath: "/no/such/binary/anywhere"),
            argumentPrefix: [],
            workingDirectory: nil,
            environment: nil
        )
        let manager = MCPServerManager(launcher: launcher)
        do {
            _ = try manager.start(voiceName: "kiln-test")
            XCTFail("expected launchFailed throw")
        } catch MCPServerError.launchFailed {
            // expected
        } catch {
            XCTFail("expected launchFailed, got \(error)")
        }
        if case .failed(let message) = manager.status {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected status to be .failed, got \(manager.status)")
        }
    }
}
